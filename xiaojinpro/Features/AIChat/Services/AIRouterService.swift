//
//  AIRouterService.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - Chat Completion Request (OpenAI Compatible)
struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    var stream: Bool = true
    var temperature: Double?
    var maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxTokens = "max_tokens"
    }
}

// MARK: - Chat Message (OpenAI Format)
struct ChatMessage: Codable {
    let role: String
    let content: ChatContent

    init(role: AIMessageRole, text: String) {
        self.role = role.rawValue
        self.content = .text(text)
    }

    init(role: AIMessageRole, parts: [ChatContentPart]) {
        self.role = role.rawValue
        self.content = .parts(parts)
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)

        // Try to decode as string first
        if let text = try? container.decode(String.self, forKey: .content) {
            content = .text(text)
        } else {
            // Try to decode as array of parts
            let parts = try container.decode([ChatContentPart].self, forKey: .content)
            content = .parts(parts)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)

        switch content {
        case .text(let text):
            try container.encode(text, forKey: .content)
        case .parts(let parts):
            try container.encode(parts, forKey: .content)
        }
    }
}

// MARK: - Chat Content
enum ChatContent: Codable {
    case text(String)
    case parts([ChatContentPart])
}

// MARK: - Chat Content Part
struct ChatContentPart: Codable {
    let type: String
    var text: String?
    var imageUrl: ImageUrl?
    var videoUrl: VideoUrl?
    var fileUrl: FileUrl?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
        case videoUrl = "video_url"
        case fileUrl = "file_url"
    }

    static func text(_ content: String) -> ChatContentPart {
        ChatContentPart(type: "text", text: content)
    }

    static func image(_ url: String) -> ChatContentPart {
        ChatContentPart(type: "image_url", imageUrl: ImageUrl(url: url))
    }

    static func video(_ url: String) -> ChatContentPart {
        ChatContentPart(type: "video_url", videoUrl: VideoUrl(url: url))
    }

    static func file(_ url: String, mimeType: String? = nil) -> ChatContentPart {
        ChatContentPart(type: "file_url", fileUrl: FileUrl(url: url, mimeType: mimeType))
    }
}

struct ImageUrl: Codable {
    let url: String
}

struct VideoUrl: Codable {
    let url: String
}

struct FileUrl: Codable {
    let url: String
    let mimeType: String?

    enum CodingKeys: String, CodingKey {
        case url
        case mimeType = "mime_type"
    }
}

// MARK: - Chat Completion Response (SSE)
struct ChatCompletionChunk: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [ChunkChoice]?
    let usage: UsageInfo?
}

struct ChunkChoice: Codable {
    let index: Int?
    let delta: ChunkDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }
}

struct ChunkDelta: Codable {
    let role: String?
    let content: String?
}

struct UsageInfo: Codable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - AI Router Service
@MainActor
class AIRouterService: ObservableObject {
    static let shared = AIRouterService()

    private let secretStore = SecretStoreService.shared
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    @Published var availableModels: [AIModel] = AIModel.defaultModels
    @Published var isLoadingModels = false

    /// Cached backend credentials
    private var backendCredentials: BackendCredentials?

    private init() {
        decoder = JSONDecoder()
        // 不使用 .convertFromSnakeCase，因为 Model 已定义 CodingKeys
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        // 不使用 .convertToSnakeCase，因为 Model 已定义 CodingKeys
    }

    // MARK: - Backend Credentials

    /// Get backend credentials (fetches from secret store if needed)
    private func getCredentials() async throws -> BackendCredentials {
        try await secretStore.getBackendCredentials()
    }

    // MARK: - Models API

    func fetchModels() async throws {
        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            let credentials = try await getCredentials()

            var request = URLRequest(url: URL(string: "\(credentials.baseURL)/v1/models/extended")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                // Fall back to default models
                availableModels = AIModel.defaultModels
                return
            }

            let modelsResponse = try decoder.decode(ModelsResponse.self, from: data)
            availableModels = modelsResponse.data
        } catch {
            // Fall back to default models on error
            print("Failed to fetch models: \(error)")
            availableModels = AIModel.defaultModels
        }
    }

    // MARK: - Chat Completions API (Streaming)

    func streamChatCompletion(
        model: String,
        messages: [AIMessage],
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let credentials = try await self.getCredentials()

                    // Build chat messages
                    var chatMessages: [ChatMessage] = []

                    // Add system prompt if provided
                    if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
                        chatMessages.append(ChatMessage(role: .system, text: systemPrompt))
                    }

                    // Convert AI messages to chat messages
                    for message in messages {
                        if let parts = message.contentParts, !parts.isEmpty {
                            // Multimodal message
                            let chatParts = parts.map { part -> ChatContentPart in
                                switch part {
                                case .text(let text):
                                    return .text(text)
                                case .imageUrl(let url):
                                    return .image(url)
                                case .videoUrl(let url):
                                    return .video(url)
                                case .fileUrl(let url, let mimeType):
                                    return .file(url, mimeType: mimeType)
                                }
                            }
                            chatMessages.append(ChatMessage(role: message.role, parts: chatParts))
                        } else {
                            // Text-only message
                            chatMessages.append(ChatMessage(role: message.role, text: message.content))
                        }
                    }

                    let requestBody = ChatCompletionRequest(
                        model: model,
                        messages: chatMessages,
                        stream: true,
                        temperature: temperature,
                        maxTokens: maxTokens
                    )

                    var request = URLRequest(url: URL(string: "\(credentials.baseURL)/v1/chat/completions")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try self.encoder.encode(requestBody)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse
                    }

                    guard 200..<300 ~= httpResponse.statusCode else {
                        throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
                    }

                    // Use lines iterator for proper UTF-8 handling
                    for try await line in bytes.lines {
                        // Parse data line
                        if line.hasPrefix("data: ") {
                            let dataString = String(line.dropFirst(6))

                            if dataString == "[DONE]" {
                                continuation.finish()
                                return
                            }

                            if let data = dataString.data(using: .utf8),
                               let chunk = try? self.decoder.decode(ChatCompletionChunk.self, from: data),
                               let content = chunk.choices?.first?.delta?.content {
                                continuation.yield(content)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Non-Streaming Chat Completion

    func chatCompletion(
        model: String,
        messages: [AIMessage],
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) async throws -> (content: String, usage: UsageInfo?) {
        let credentials = try await getCredentials()

        // Build chat messages
        var chatMessages: [ChatMessage] = []

        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            chatMessages.append(ChatMessage(role: .system, text: systemPrompt))
        }

        for message in messages {
            chatMessages.append(ChatMessage(role: message.role, text: message.content))
        }

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: chatMessages,
            stream: false,
            temperature: temperature,
            maxTokens: maxTokens
        )

        var request = URLRequest(url: URL(string: "\(credentials.baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }

        let chunk = try decoder.decode(ChatCompletionChunk.self, from: data)
        let content = chunk.choices?.first?.delta?.content ?? ""

        return (content, chunk.usage)
    }
}
