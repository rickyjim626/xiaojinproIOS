//
//  Skill.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - Skill Category
enum SkillCategory: String, Codable, CaseIterable {
    case devops = "DevOps"
    case videoEdit = "VideoEdit"
    case timeline = "Timeline"
    case admin = "Admin"
    case general = "General"

    var displayName: String {
        switch self {
        case .devops: return "DevOps"
        case .videoEdit: return "视频编辑"
        case .timeline: return "时间线"
        case .admin: return "管理"
        case .general: return "通用"
        }
    }

    var icon: String {
        switch self {
        case .devops: return "server.rack"
        case .videoEdit: return "film"
        case .timeline: return "timeline.selection"
        case .admin: return "gearshape.2"
        case .general: return "wand.and.stars"
        }
    }

    var color: String {
        switch self {
        case .devops: return "blue"
        case .videoEdit: return "purple"
        case .timeline: return "orange"
        case .admin: return "red"
        case .general: return "green"
        }
    }
}

// MARK: - Skill Parameter Schema
struct SkillParameterSchema: Codable {
    let type: String
    let properties: [String: PropertySchema]?
    let required: [String]?

    struct PropertySchema: Codable {
        let type: String
        let description: String?
        let enumValues: [String]?
        let defaultValue: AnyCodable?
        let format: String?
        let minimum: Double?
        let maximum: Double?

        enum CodingKeys: String, CodingKey {
            case type
            case description
            case enumValues = "enum"
            case defaultValue = "default"
            case format
            case minimum
            case maximum
        }
    }
}

// MARK: - Skill
struct Skill: Codable, Identifiable, Equatable {
    let name: String
    let displayName: String
    let description: String
    let category: SkillCategory
    let parameters: SkillParameterSchema
    let requiresConfirmation: Bool
    let permissions: [String]

    var id: String { name }

    static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.name == rhs.name
    }

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case description
        case category
        case parameters
        case requiresConfirmation = "requires_confirmation"
        case permissions
    }
}

// MARK: - Skills Response
struct SkillsResponse: Codable {
    let skills: [Skill]
}

// MARK: - Execute Skill Request
struct ExecuteSkillRequest: Codable {
    let arguments: [String: AnyCodable]
    let conversationId: String?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case arguments
        case conversationId = "conversation_id"
        case requestId = "request_id"
    }

    init(arguments: [String: Any], conversationId: String? = nil) {
        self.arguments = arguments.mapValues { AnyCodable($0) }
        self.conversationId = conversationId
        self.requestId = UUID().uuidString
    }
}

// MARK: - Execute Skill Response
struct ExecuteSkillResponse: Codable {
    let taskId: String
    let status: TaskStatus

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case status
    }
}
