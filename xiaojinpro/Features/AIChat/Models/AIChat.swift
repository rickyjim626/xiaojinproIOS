//
//  AIChat.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - AI Conversation (Cloud Synced)
struct AIConversation: Codable, Identifiable, Equatable {
    let id: String
    var title: String?
    var model: String
    var systemPrompt: String?
    var temperature: Double?
    var maxTokens: Int?
    var messageCount: Int
    var totalTokens: Int
    var isArchived: Bool
    var lastMessageAt: Date?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case model
        case systemPrompt = "system_prompt"
        case temperature
        case maxTokens = "max_tokens"
        case messageCount = "message_count"
        case totalTokens = "total_tokens"
        case isArchived = "is_archived"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayTitle: String {
        title ?? "新对话"
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastMessageAt ?? updatedAt, relativeTo: Date())
    }

    static func == (lhs: AIConversation, rhs: AIConversation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - AI Message Role
enum AIMessageRole: String, Codable {
    case system
    case user
    case assistant
}

// MARK: - AI Content Part (Multimodal Support)
enum AIContentPart: Codable, Equatable {
    case text(String)
    case imageUrl(String)
    case videoUrl(String)
    case fileUrl(String, mimeType: String?)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case url
        case mimeType = "mime_type"
        case imageUrl = "image_url"
        case videoUrl = "video_url"
        case fileUrl = "file_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image_url":
            let urlContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .imageUrl)
            let url = try urlContainer.decode(String.self, forKey: .url)
            self = .imageUrl(url)
        case "video_url":
            let urlContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .videoUrl)
            let url = try urlContainer.decode(String.self, forKey: .url)
            self = .videoUrl(url)
        case "file_url":
            let urlContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .fileUrl)
            let url = try urlContainer.decode(String.self, forKey: .url)
            let mimeType = try urlContainer.decodeIfPresent(String.self, forKey: .mimeType)
            self = .fileUrl(url, mimeType: mimeType)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageUrl(let url):
            try container.encode("image_url", forKey: .type)
            var urlContainer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .imageUrl)
            try urlContainer.encode(url, forKey: .url)
        case .videoUrl(let url):
            try container.encode("video_url", forKey: .type)
            var urlContainer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .videoUrl)
            try urlContainer.encode(url, forKey: .url)
        case .fileUrl(let url, let mimeType):
            try container.encode("file_url", forKey: .type)
            var urlContainer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .fileUrl)
            try urlContainer.encode(url, forKey: .url)
            try urlContainer.encodeIfPresent(mimeType, forKey: .mimeType)
        }
    }

    var textContent: String? {
        if case .text(let text) = self {
            return text
        }
        return nil
    }
}

// MARK: - AI Message
struct AIMessage: Codable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let role: AIMessageRole
    var content: String
    var contentParts: [AIContentPart]?
    var promptTokens: Int?
    var completionTokens: Int?
    var modelUsed: String?
    var finishReason: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case role
        case content
        case contentParts = "content_parts"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case modelUsed = "model_used"
        case finishReason = "finish_reason"
        case createdAt = "created_at"
    }

    var isUser: Bool { role == .user }
    var isAssistant: Bool { role == .assistant }

    var hasAttachments: Bool {
        guard let parts = contentParts else { return false }
        return parts.contains { part in
            switch part {
            case .text: return false
            default: return true
            }
        }
    }

    var attachmentUrls: [String] {
        guard let parts = contentParts else { return [] }
        return parts.compactMap { part in
            switch part {
            case .imageUrl(let url), .videoUrl(let url), .fileUrl(let url, _):
                return url
            case .text:
                return nil
            }
        }
    }

    static func == (lhs: AIMessage, rhs: AIMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - AI Attachment
struct AIAttachment: Codable, Identifiable {
    let id: String
    let conversationId: String
    let messageId: String?
    let fileName: String
    let fileType: String
    let fileSize: Int
    let mimeType: String?
    let storageKey: String
    var storedUrl: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case fileName = "file_name"
        case fileType = "file_type"
        case fileSize = "file_size"
        case mimeType = "mime_type"
        case storageKey = "storage_key"
        case storedUrl = "stored_url"
        case createdAt = "created_at"
    }
}

// MARK: - Create Conversation Request
struct CreateAIConversationRequest: Codable {
    var title: String?
    var model: String
    var systemPrompt: String?
    var temperature: Double?
    var maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case model
        case systemPrompt = "system_prompt"
        case temperature
        case maxTokens = "max_tokens"
    }
}

// MARK: - Update Conversation Request
struct UpdateAIConversationRequest: Codable {
    var title: String?
    var model: String?
    var systemPrompt: String?
    var temperature: Double?
    var maxTokens: Int?
    var isArchived: Bool?

    enum CodingKeys: String, CodingKey {
        case title
        case model
        case systemPrompt = "system_prompt"
        case temperature
        case maxTokens = "max_tokens"
        case isArchived = "is_archived"
    }
}

// MARK: - Create Message Request
struct CreateAIMessageRequest: Codable {
    let role: AIMessageRole
    let content: String
    var contentParts: [AIContentPart]?
    var attachmentIds: [String]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case contentParts = "content_parts"
        case attachmentIds = "attachment_ids"
    }
}

// MARK: - Create Attachment Request
struct CreateAttachmentRequest: Codable {
    let fileName: String
    let fileType: String
    let fileSize: Int
    let mimeType: String?

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case fileType = "file_type"
        case fileSize = "file_size"
        case mimeType = "mime_type"
    }
}

// MARK: - Create Attachment Response
struct CreateAttachmentResponse: Codable {
    let attachmentId: String
    let uploadUrl: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case attachmentId = "attachment_id"
        case uploadUrl = "upload_url"
        case expiresAt = "expires_at"
    }
}

// MARK: - Paginated Response
struct PaginatedResponse<T: Codable>: Codable {
    let data: [T]
    let hasMore: Bool
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}
