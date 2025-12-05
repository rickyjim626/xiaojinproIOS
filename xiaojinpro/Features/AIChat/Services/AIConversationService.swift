//
//  AIConversationService.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - AI Conversation Service (Cloud Sync)
@MainActor
class AIConversationService: ObservableObject {
    static let shared = AIConversationService()

    private let baseURL = "https://auth.xiaojinpro.com/v1/ai"
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Conversations API

    func listConversations(
        includeArchived: Bool = false,
        limit: Int = 50,
        cursor: String? = nil,
        search: String? = nil
    ) async throws -> PaginatedResponse<AIConversation> {
        guard let token = await AuthManager.shared.accessToken else {
            throw APIError.unauthorized
        }

        var urlComponents = URLComponents(string: "\(baseURL)/conversations")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "include_archived", value: String(includeArchived)),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        if let search = search, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }

        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }

        return try decoder.decode(PaginatedResponse<AIConversation>.self, from: data)
    }

    func getConversation(id: String) async throws -> AIConversation {
        guard let token = await AuthManager.shared.accessToken else {
            throw APIError.unauthorized
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/conversations/\(id)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }

        return try decoder.decode(AIConversation.self, from: data)
    }

    func createConversation(
        title: String? = nil,
        model: String = "claude-sonnet-4.5",
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) async throws -> AIConversation {
        guard let token = await AuthManager.shared.accessToken else {
            throw APIError.unauthorized
        }

        let body = CreateAIConversationRequest(
            title: title,
            model: model,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )

        var request = URLRequest(url: URL(string: "\(baseURL)/conversations")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }

        return try decoder.decode(AIConversation.self, from: data)
    }

    func updateConversation(
        id: String,
        title: String? = nil,
        model: String? = nil,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        isArchived: Bool? = nil
    ) async throws -> AIConversation {
        guard let token = await AuthManager.shared.accessToken else {
            throw APIError.unauthorized
        }

        let body = UpdateAIConversationRequest(
            title: title,
            model: model,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens,
            isArchived: isArchived
        )

        var request = URLRequest(url: URL(string: "\(baseURL)/conversations/\(id)")!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }

        return try decoder.decode(AIConversation.self, from: data)
    }

    func deleteConversation(id: String) async throws {
        guard let token = await AuthManager.shared.accessToken else {
            throw APIError.unauthorized
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/conversations/\(id)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }
    }

    // MARK: - Messages API

    func listMessages(
        conversationId: String,
        limit: Int = 100,
        before: String? = nil,
        after: String? = nil
    ) async throws -> PaginatedResponse<AIMessage> {
        guard let token = await AuthManager.shared.accessToken else {
            throw APIError.unauthorized
        }

        var urlComponents = URLComponents(string: "\(baseURL)/conversations/\(conversationId)/messages")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let before = before {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }

        if let after = after {
            queryItems.append(URLQueryItem(name: "after", value: after))
        }

        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }

        return try decoder.decode(PaginatedResponse<AIMessage>.self, from: data)
    }

    func createMessage(
        conversationId: String,
        role: AIMessageRole,
        content: String,
        contentParts: [AIContentPart]? = nil,
        attachmentIds: [String]? = nil
    ) async throws -> AIMessage {
        guard let token = await AuthManager.shared.accessToken else {
            throw APIError.unauthorized
        }

        let body = CreateAIMessageRequest(
            role: role,
            content: content,
            contentParts: contentParts,
            attachmentIds: attachmentIds
        )

        var request = URLRequest(url: URL(string: "\(baseURL)/conversations/\(conversationId)/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }

        return try decoder.decode(AIMessage.self, from: data)
    }

    func deleteMessage(conversationId: String, messageId: String) async throws {
        guard let token = await AuthManager.shared.accessToken else {
            throw APIError.unauthorized
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/conversations/\(conversationId)/messages/\(messageId)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }
    }

    // MARK: - Attachments API

    func createAttachment(
        conversationId: String,
        fileName: String,
        fileType: String,
        fileSize: Int,
        mimeType: String?
    ) async throws -> CreateAttachmentResponse {
        guard let token = await AuthManager.shared.accessToken else {
            throw APIError.unauthorized
        }

        let body = CreateAttachmentRequest(
            fileName: fileName,
            fileType: fileType,
            fileSize: fileSize,
            mimeType: mimeType
        )

        var request = URLRequest(url: URL(string: "\(baseURL)/conversations/\(conversationId)/attachments")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }

        return try decoder.decode(CreateAttachmentResponse.self, from: data)
    }

    func uploadAttachment(to uploadUrl: String, data: Data, mimeType: String) async throws {
        guard let url = URL(string: uploadUrl) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: "Upload failed")
        }
    }

    func listAttachments(conversationId: String) async throws -> [AIAttachment] {
        guard let token = await AuthManager.shared.accessToken else {
            throw APIError.unauthorized
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/conversations/\(conversationId)/attachments")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }

        return try decoder.decode([AIAttachment].self, from: data)
    }
}
