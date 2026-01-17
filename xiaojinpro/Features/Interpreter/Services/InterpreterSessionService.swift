//
//  InterpreterSessionService.swift
//  xiaojinpro
//
//  Session-based interpreter API service
//  Handles session lifecycle and SSE streaming
//

import Foundation

// MARK: - Interpreter Session Service

@MainActor
class InterpreterSessionService: ObservableObject {

    static let shared = InterpreterSessionService()

    // Use auth base URL for interpreter API
    private let baseURL = "https://auth.xiaojinpro.com"
    private let authManager = AuthManager.shared

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    @Published var sessionId: String?
    @Published var isSessionActive = false
    @Published var streamUrl: String?
    @Published var error: String?

    // SSE connection
    private var sseTask: URLSessionDataTask?
    private var sseBuffer = ""

    // Callback for SSE events
    var onSSEEvent: ((InterpreterSSEEvent) -> Void)?

    private init() {}

    // MARK: - Auth Helper

    /// Get JWT access token, throws if not authenticated
    private func getAccessToken() async throws -> String {
        guard let token = await authManager.accessToken else {
            throw InterpreterError.notAuthenticated
        }
        return token
    }

    // MARK: - Session Lifecycle

    /// Create a new interpreter session
    func createSession(config: SessionConfig) async throws -> CreateSessionResponse {
        let token = try await getAccessToken()

        let url = URL(string: "\(baseURL)/asr/v1/interpreter/sessions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(config)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        let result = try decoder.decode(CreateSessionResponse.self, from: data)
        sessionId = result.sessionId
        streamUrl = result.streamUrl
        isSessionActive = true
        error = nil

        print("[InterpreterSession] Created session: \(result.sessionId)")
        return result
    }

    /// Process an audio segment (async - returns immediately, result via SSE)
    func processAudio(
        audioData: Data,
        format: String = "aac",
        startTime: TimeInterval,
        endTime: TimeInterval,
        isFinal: Bool = false
    ) async throws -> ProcessAcceptedResponse {
        guard let sessionId = sessionId else {
            throw InterpreterError.networkError("No active session")
        }

        let token = try await getAccessToken()

        let requestBody = ProcessAudioRequest(
            audioBase64: audioData.base64EncodedString(),
            audioFormat: format,
            startTime: startTime,
            endTime: endTime,
            isFinal: isFinal
        )

        let url = URL(string: "\(baseURL)/asr/v1/interpreter/sessions/\(sessionId)/process")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        // Accept both 200 and 202
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InterpreterError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 202 {
            // Async processing - result will come via SSE
            return try decoder.decode(ProcessAcceptedResponse.self, from: data)
        } else if 200..<300 ~= httpResponse.statusCode {
            // Sync processing (fallback) - create a synthetic accepted response
            let syncResult = try decoder.decode(ProcessAudioResponse.self, from: data)
            return ProcessAcceptedResponse(
                segmentId: UUID().uuidString,
                segmentIndex: syncResult.segmentIndex,
                queuedAt: ISO8601DateFormatter().string(from: Date())
            )
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw InterpreterError.networkError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
    }

    /// Get session status
    func getSessionStatus() async throws -> SessionStatusResponse {
        guard let sessionId = sessionId else {
            throw InterpreterError.networkError("No active session")
        }

        let token = try await getAccessToken()

        let url = URL(string: "\(baseURL)/asr/v1/interpreter/sessions/\(sessionId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        return try decoder.decode(SessionStatusResponse.self, from: data)
    }

    /// End the session
    func endSession() async throws -> EndSessionResponse {
        guard let sessionId = sessionId else {
            throw InterpreterError.networkError("No active session")
        }

        // Stop SSE first
        stopSSE()

        defer {
            self.sessionId = nil
            self.streamUrl = nil
            self.isSessionActive = false
        }

        let token = try await getAccessToken()

        let url = URL(string: "\(baseURL)/asr/v1/interpreter/sessions/\(sessionId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        let result = try decoder.decode(EndSessionResponse.self, from: data)
        if let summary = result.summary {
            print("[InterpreterSession] Ended session: \(summary.totalSegments) segments")
        } else {
            print("[InterpreterSession] Ended session (no segments processed)")
        }
        return result
    }

    /// List audio segments stored in R2
    func listAudioSegments() async throws -> AudioListResponse {
        guard let sessionId = sessionId else {
            throw InterpreterError.networkError("No active session")
        }

        let token = try await getAccessToken()

        let url = URL(string: "\(baseURL)/asr/v1/interpreter/sessions/\(sessionId)/audio")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        return try decoder.decode(AudioListResponse.self, from: data)
    }

    // MARK: - SSE Streaming

    /// Start listening to SSE stream
    func startSSE() async {
        guard let sessionId = sessionId else {
            print("[InterpreterSession] Cannot start SSE: no session")
            return
        }

        do {
            let token = try await getAccessToken()
            let urlString = "\(baseURL)/asr/v1/interpreter/sessions/\(sessionId)/stream"

            guard let url = URL(string: urlString) else {
                print("[InterpreterSession] Invalid SSE URL")
                return
            }

            var request = URLRequest(url: url)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = TimeInterval.infinity

            let session = URLSession(configuration: .default, delegate: SSEDelegate(service: self), delegateQueue: nil)
            sseTask = session.dataTask(with: request)
            sseTask?.resume()

            print("[InterpreterSession] SSE started for session: \(sessionId)")
        } catch {
            print("[InterpreterSession] Failed to start SSE: \(error)")
        }
    }

    /// Stop SSE connection
    func stopSSE() {
        sseTask?.cancel()
        sseTask = nil
        sseBuffer = ""
        print("[InterpreterSession] SSE stopped")
    }

    /// Process SSE data chunk
    func handleSSEData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        sseBuffer += text

        // Parse complete events (separated by double newline)
        while let range = sseBuffer.range(of: "\n\n") {
            let eventText = String(sseBuffer[..<range.lowerBound])
            sseBuffer = String(sseBuffer[range.upperBound...])

            if let event = parseSSEEvent(eventText) {
                Task { @MainActor in
                    self.onSSEEvent?(event)
                }
            }
        }
    }

    private func parseSSEEvent(_ text: String) -> InterpreterSSEEvent? {
        var eventType = ""
        var eventData = ""

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("event:") {
                eventType = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                eventData = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            }
        }

        guard !eventType.isEmpty else { return nil }

        switch eventType {
        case "ready":
            if let data = eventData.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sessionId = json["session_id"] as? String {
                return .ready(sessionId: sessionId)
            }
        case "segment":
            if let data = eventData.data(using: .utf8),
               let segment = try? decoder.decode(SegmentEvent.self, from: data) {
                return .segment(segment)
            }
        case "error":
            if let data = eventData.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                return .error(message: message)
            }
        case "heartbeat":
            return .heartbeat
        case "ended":
            if let data = eventData.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let summaryData = try? JSONSerialization.data(withJSONObject: json["summary"] ?? [:]),
               let summary = try? decoder.decode(SessionSummaryResponse.self, from: summaryData) {
                return .ended(summary: summary)
            }
        default:
            return .unknown(event: eventType, data: eventData)
        }

        return .unknown(event: eventType, data: eventData)
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InterpreterError.networkError("Invalid response")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw InterpreterError.networkError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
    }

    /// Reset service state
    func reset() {
        stopSSE()
        sessionId = nil
        streamUrl = nil
        isSessionActive = false
        error = nil
    }
}

// MARK: - SSE Delegate

private class SSEDelegate: NSObject, URLSessionDataDelegate {
    weak var service: InterpreterSessionService?

    init(service: InterpreterSessionService) {
        self.service = service
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor in
            service?.handleSSEData(data)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[InterpreterSession] SSE error: \(error)")
        } else {
            print("[InterpreterSession] SSE completed")
        }
    }
}
