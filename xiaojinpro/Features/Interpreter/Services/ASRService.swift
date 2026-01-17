//
//  ASRService.swift
//  xiaojinpro
//
//  Automatic Speech Recognition service
//  Calls backend ASR API with AAC audio
//

import Foundation

// MARK: - ASR Service
@MainActor
class ASRService: ObservableObject {
    static let shared = ASRService()

    private let secretStore = SecretStoreService.shared
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    @Published var isProcessing = false
    @Published var error: String?

    private init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Public Methods

    /// Transcribe audio data to text
    /// - Parameters:
    ///   - audioData: AAC encoded audio data
    ///   - startTime: Start time offset
    ///   - overlapDuration: Duration of overlap with previous segment
    ///   - languageHint: Language hint (e.g., "en-US", nil for auto-detect)
    /// - Returns: ASR response with transcribed text
    func transcribe(
        audioData: Data,
        startTime: TimeInterval = 0,
        overlapDuration: TimeInterval = 0,
        languageHint: String? = nil
    ) async throws -> ASRResponse {
        isProcessing = true
        error = nil
        defer { isProcessing = false }

        do {
            let credentials = try await secretStore.getBackendCredentials()

            // Build request
            let request = ASRRequest(
                audioBase64: audioData.base64EncodedString(),
                audioFormat: "aac",
                startTime: startTime,
                overlapDuration: overlapDuration > 0 ? overlapDuration : nil,
                languageHint: languageHint
            )

            // Create URL request
            let url = URL(string: "\(credentials.baseURL)/asr/v1/align/audio")!
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.httpBody = try encoder.encode(request)
            urlRequest.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw InterpreterError.asrFailed("Invalid response")
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw InterpreterError.asrFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }

            let asrResponse = try decoder.decode(ASRResponse.self, from: data)
            return asrResponse

        } catch let interpreterError as InterpreterError {
            self.error = interpreterError.localizedDescription
            throw interpreterError
        } catch {
            let interpreterError = InterpreterError.asrFailed(error.localizedDescription)
            self.error = interpreterError.localizedDescription
            throw interpreterError
        }
    }

    /// Transcribe with retry logic
    func transcribeWithRetry(
        audioData: Data,
        startTime: TimeInterval = 0,
        overlapDuration: TimeInterval = 0,
        languageHint: String? = nil,
        maxRetries: Int = 2
    ) async throws -> ASRResponse {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                return try await transcribe(
                    audioData: audioData,
                    startTime: startTime,
                    overlapDuration: overlapDuration,
                    languageHint: languageHint
                )
            } catch {
                lastError = error
                if attempt < maxRetries {
                    // Wait before retry (exponential backoff)
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 500_000_000))
                }
            }
        }

        throw lastError ?? InterpreterError.asrFailed("Unknown error")
    }

    // MARK: - Deduplication

    /// Deduplicate overlapping transcriptions
    /// - Parameters:
    ///   - previousText: Text from previous segment
    ///   - previousEndTime: End time of previous segment
    ///   - currentText: Text from current segment (includes overlap)
    ///   - currentStartTime: Start time of current segment
    ///   - overlapDuration: Duration of overlap between segments
    /// - Returns: Deduplicated response
    func deduplicate(
        previousText: String,
        previousEndTime: TimeInterval,
        currentText: String,
        currentStartTime: TimeInterval,
        overlapDuration: TimeInterval
    ) async throws -> DeduplicateResponse {
        let credentials = try await secretStore.getBackendCredentials()

        let request = DeduplicateRequest(
            previousText: previousText,
            previousEndTime: previousEndTime,
            currentText: currentText,
            currentStartTime: currentStartTime,
            overlapDuration: overlapDuration
        )

        let url = URL(string: "\(credentials.baseURL)/asr/v1/asr/deduplicate")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(request)
        urlRequest.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InterpreterError.asrFailed("Invalid response")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw InterpreterError.asrFailed("Deduplication failed: HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        return try decoder.decode(DeduplicateResponse.self, from: data)
    }
}

// MARK: - Mock ASR Service (for testing)

#if DEBUG
class MockASRService: ASRService {
    override func transcribe(
        audioData: Data,
        startTime: TimeInterval = 0,
        overlapDuration: TimeInterval = 0,
        languageHint: String? = nil
    ) async throws -> ASRResponse {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Return mock response
        return ASRResponse(
            text: "Hello, how are you doing today?",
            confidence: 0.95,
            words: [
                ASRWord(word: "Hello", start: 0.0, end: 0.5, confidence: 0.98),
                ASRWord(word: "how", start: 0.6, end: 0.8, confidence: 0.95),
                ASRWord(word: "are", start: 0.9, end: 1.0, confidence: 0.96),
                ASRWord(word: "you", start: 1.1, end: 1.3, confidence: 0.97),
                ASRWord(word: "doing", start: 1.4, end: 1.7, confidence: 0.94),
                ASRWord(word: "today", start: 1.8, end: 2.2, confidence: 0.93)
            ],
            language: "en-US",
            detectedLanguage: "en"
        )
    }
}
#endif
