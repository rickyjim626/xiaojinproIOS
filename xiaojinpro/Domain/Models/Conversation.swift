//
//  Conversation.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - Conversation Type
enum ConversationType: String, Codable, CaseIterable {
    case chat = "chat"
    case admin = "admin"
    case workflow = "workflow"

    var displayName: String {
        switch self {
        case .chat: return "对话"
        case .admin: return "管理"
        case .workflow: return "工作流"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .admin: return "gearshape.2"
        case .workflow: return "arrow.triangle.branch"
        }
    }
}

// MARK: - Conversation
struct Conversation: Codable, Identifiable {
    let id: String
    let tenantId: String?
    let type: ConversationType
    var title: String?
    var systemPrompt: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case tenantId = "tenant_id"
        case type
        case title
        case systemPrompt = "system_prompt"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayTitle: String {
        title ?? "新对话"
    }
}

// MARK: - Message Role
enum MessageRole: String, Codable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
    case tool = "tool"
}

// MARK: - Tool Call
struct ToolCall: Codable, Identifiable {
    let id: String
    let name: String
    let arguments: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case arguments
    }
}

// MARK: - Message
struct Message: Codable, Identifiable {
    let id: String
    let conversationId: String
    let role: MessageRole
    var content: String
    let toolCalls: [ToolCall]?
    let toolCallId: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case createdAt = "created_at"
    }

    var isUser: Bool {
        role == .user
    }

    var isAssistant: Bool {
        role == .assistant
    }

    var hasToolCalls: Bool {
        toolCalls != nil && !toolCalls!.isEmpty
    }
}

// MARK: - Create Conversation Request
struct CreateConversationRequest: Codable {
    let type: ConversationType
    let title: String?
    let systemPrompt: String?

    enum CodingKeys: String, CodingKey {
        case type
        case title
        case systemPrompt = "system_prompt"
    }
}

// MARK: - Send Message Request
struct SendMessageRequest: Codable {
    let content: String
    let context: MessageContext?

    struct MessageContext: Codable {
        let projectId: String?
        let selectedResources: [String]?

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case selectedResources = "selected_resources"
        }
    }
}

// MARK: - Messages Response
struct MessagesResponse: Codable {
    let messages: [Message]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case messages
        case hasMore = "has_more"
    }
}
