//
//  InterpreterSessionModels.swift
//  xiaojinpro
//
//  Models for session-based interpreter API
//  Note: Decoder uses .convertFromSnakeCase, so no CodingKeys needed
//

import Foundation

// MARK: - Session Config

struct SessionConfig: Codable {
    let targetLanguage: String
    let translationPreset: String?
    let overlapDuration: Double
    let enableTranslation: Bool

    static func `default`(targetLanguage: String = "zh") -> SessionConfig {
        SessionConfig(
            targetLanguage: targetLanguage,
            translationPreset: nil,  // Use Gemini Flash fallback in backend
            overlapDuration: 2.0,
            enableTranslation: true
        )
    }
}

// MARK: - Create Session Response

struct CreateSessionResponse: Codable {
    let sessionId: String
    let config: SessionConfigResponse
    let expiresAt: String
    let streamUrl: String?
}

struct SessionConfigResponse: Codable {
    let targetLanguage: String
    let translationPreset: String?
    let overlapDuration: Double
    let asrProvider: String?
    let enableTranslation: Bool
}

// MARK: - Process Request

struct ProcessAudioRequest: Codable {
    let audioBase64: String
    let audioFormat: String
    let startTime: Double
    let endTime: Double
    let isFinal: Bool
}

// MARK: - Process Response

struct ProcessAudioResponse: Codable {
    let segmentIndex: Int
    let originalText: String
    let deduplicatedText: String
    let translatedText: String?
    let detectedLanguage: String?
    let isDuplicate: Bool
    let audioStored: Bool
    let r2Key: String?
}

// MARK: - Session Status Response

struct SessionStatusResponse: Codable {
    let sessionId: String
    let config: SessionConfigResponse
    let state: SessionStateResponse
    let stats: SessionStatsResponse
    let expiresAt: String
}

struct SessionStateResponse: Codable {
    let lastSegmentText: String
    let lastSegmentEndTime: Double
    let detectedLanguage: String?
    let segmentCount: Int
}

struct SessionStatsResponse: Codable {
    let totalAudioDuration: Double
    let totalSegments: Int
    let totalCharsTranscribed: Int
    let totalCharsTranslated: Int
}

// MARK: - End Session Response

struct EndSessionResponse: Codable {
    let sessionId: String
    let summary: SessionSummaryResponse?  // Optional - may be nil if no audio processed
}

struct SessionSummaryResponse: Codable {
    let totalDuration: Double
    let totalSegments: Int
    let audioFiles: [String]?
}

// MARK: - Audio List Response

struct AudioSegmentInfo: Codable, Identifiable {
    var id: Int { index }
    let index: Int
    let r2Key: String
    let start: Double
    let end: Double
    let presignUrl: String?
}

struct AudioListResponse: Codable {
    let segments: [AudioSegmentInfo]
}

// MARK: - SSE Events

enum InterpreterSSEEvent {
    case ready(sessionId: String)
    case segment(SegmentEvent)
    case error(message: String)
    case heartbeat
    case ended(summary: SessionSummaryResponse)
    case unknown(event: String, data: String)
}

/// Backend timing breakdown for a segment
struct BackendSegmentTimings: Codable {
    let sessionFetchMs: Int?
    let asrMs: Int?
    let r2UploadMs: Int?
    let dedupeMs: Int?
    let translateMs: Int?

    var total: Int {
        (sessionFetchMs ?? 0) + (asrMs ?? 0) + (r2UploadMs ?? 0) + (dedupeMs ?? 0) + (translateMs ?? 0)
    }
}

struct SegmentEvent: Codable {
    let segmentId: String
    let segmentIndex: Int
    let originalText: String
    let deduplicatedText: String
    let translatedText: String?
    let detectedLanguage: String?
    let isDuplicate: Bool
    let r2Key: String?
    let latencyMs: Int?
    /// Detailed timing breakdown from backend
    let timings: BackendSegmentTimings?

    // Convenience accessors matching old names
    var index: Int { segmentIndex }
    var deduplicated: String { deduplicatedText }
    var translated: String? { translatedText }
}

// MARK: - Accepted Response (for async process)

struct ProcessAcceptedResponse: Codable {
    let segmentId: String
    let segmentIndex: Int
    let queuedAt: String
}
