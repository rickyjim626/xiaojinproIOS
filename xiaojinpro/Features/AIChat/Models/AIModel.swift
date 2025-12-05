//
//  AIModel.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - AI Model
struct AIModel: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let provider: String
    let capabilities: AIModelCapabilities?
    let contextLength: Int?
    let maxOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case provider
        case capabilities
        case contextLength = "context_length"
        case maxOutputTokens = "max_output_tokens"
    }

    var displayName: String {
        name
    }

    var providerIcon: String {
        switch provider.lowercased() {
        case "anthropic":
            return "sparkles"
        case "google":
            return "globe"
        case "openai":
            return "brain"
        default:
            return "cpu"
        }
    }

    var isThinkingModel: Bool {
        id.contains("thinking")
    }

    static func == (lhs: AIModel, rhs: AIModel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - AI Model Capabilities
struct AIModelCapabilities: Codable, Equatable, Hashable {
    let text: Bool?
    let vision: Bool?
    let video: Bool?
    let tools: Bool?
    let streaming: Bool?
    let thinkingMode: Bool?

    enum CodingKeys: String, CodingKey {
        case text
        case vision
        case video
        case tools
        case streaming
        case thinkingMode = "thinking_mode"
    }

    var supportsVision: Bool { vision ?? false }
    var supportsVideo: Bool { video ?? false }
    var supportsStreaming: Bool { streaming ?? true }
}

// MARK: - Models Response
struct ModelsResponse: Codable {
    let data: [AIModel]
}

// MARK: - Default Models
extension AIModel {
    static let defaultModels: [AIModel] = [
        AIModel(
            id: "claude-sonnet-4.5",
            name: "Claude Sonnet 4.5",
            provider: "Anthropic",
            capabilities: AIModelCapabilities(
                text: true,
                vision: true,
                video: false,
                tools: true,
                streaming: true,
                thinkingMode: false
            ),
            contextLength: 200000,
            maxOutputTokens: 8192
        ),
        AIModel(
            id: "claude-sonnet-4.5-thinking",
            name: "Claude Sonnet 4.5 Thinking",
            provider: "Anthropic",
            capabilities: AIModelCapabilities(
                text: true,
                vision: true,
                video: false,
                tools: true,
                streaming: true,
                thinkingMode: true
            ),
            contextLength: 200000,
            maxOutputTokens: 16384
        ),
        AIModel(
            id: "claude-opus-4.1",
            name: "Claude Opus 4.1",
            provider: "Anthropic",
            capabilities: AIModelCapabilities(
                text: true,
                vision: true,
                video: false,
                tools: true,
                streaming: true,
                thinkingMode: false
            ),
            contextLength: 200000,
            maxOutputTokens: 8192
        ),
        AIModel(
            id: "gemini-3-pro-preview",
            name: "Gemini 3 Pro",
            provider: "Google",
            capabilities: AIModelCapabilities(
                text: true,
                vision: true,
                video: true,
                tools: true,
                streaming: true,
                thinkingMode: false
            ),
            contextLength: 1000000,
            maxOutputTokens: 8192
        )
    ]

    static var defaultModel: AIModel {
        defaultModels.first { $0.id == "claude-sonnet-4.5" } ?? defaultModels[0]
    }
}
