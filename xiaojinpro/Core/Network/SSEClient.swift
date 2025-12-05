//
//  SSEClient.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - SSE Event
struct SSEEvent: Identifiable {
    let id = UUID()
    let event: String
    let data: String

    static func parse(_ eventString: String) -> SSEEvent? {
        var event = "message"
        var data = ""

        for line in eventString.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)
            if lineStr.hasPrefix("event:") {
                event = String(lineStr.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if lineStr.hasPrefix("data:") {
                data = String(lineStr.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }

        guard !data.isEmpty || !event.isEmpty else { return nil }
        return SSEEvent(event: event, data: data)
    }
}

// MARK: - Stream Event Types
enum StreamEventType: String, Codable {
    case textDelta = "text_delta"
    case toolCallStarted = "tool_call_started"
    case toolCallProgress = "tool_call_progress"
    case toolCallResult = "tool_call_result"
    case error = "error"
    case done = "done"
}

// MARK: - Stream Event Data
struct TextDeltaEvent: Codable {
    let content: String
}

struct ToolCallStartedEvent: Codable {
    let taskId: String
    let skill: String
    let args: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case skill
        case args
    }
}

struct ToolCallProgressEvent: Codable {
    let taskId: String
    let progress: Int
    let message: String?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case progress
        case message
    }
}

struct ToolCallResultEvent: Codable {
    let taskId: String
    let status: String
    let result: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case status
        case result
    }
}

// MARK: - AnyCodable for dynamic JSON
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unable to encode value"
                )
            )
        }
    }
}

// MARK: - SSE Client
actor SSEClient {
    private var task: Task<Void, Never>?

    func connect(
        to url: URL,
        body: Data?,
        token: String?,
        onEvent: @escaping (SSEEvent) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = body != nil ? "POST" : "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw APIError.invalidResponse
        }

        var buffer = ""
        for try await byte in bytes {
            buffer.append(Character(UnicodeScalar(byte)))

            while let eventEnd = buffer.range(of: "\n\n") {
                let eventString = String(buffer[..<eventEnd.lowerBound])
                buffer.removeSubrange(..<eventEnd.upperBound)

                if let event = SSEEvent.parse(eventString) {
                    onEvent(event)
                }
            }
        }
    }

    func disconnect() {
        task?.cancel()
        task = nil
    }
}
