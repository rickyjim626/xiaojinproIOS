//
//  InterpreterModels.swift
//  xiaojinpro
//
//  Data models for real-time interpreter feature
//

import Foundation

// MARK: - Interpreter Session
struct InterpreterSession: Codable, Identifiable, Equatable {
    let id: String
    var segments: [InterpreterSegment]
    var createdAt: Date
    var sourceLanguage: String
    var targetLanguage: String
    var totalDuration: TimeInterval

    init(
        id: String = UUID().uuidString,
        segments: [InterpreterSegment] = [],
        createdAt: Date = Date(),
        sourceLanguage: String = "en-US",
        targetLanguage: String = "zh-CN",
        totalDuration: TimeInterval = 0
    ) {
        self.id = id
        self.segments = segments
        self.createdAt = createdAt
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.totalDuration = totalDuration
    }
}

// MARK: - Interpreter Segment
struct InterpreterSegment: Codable, Identifiable, Equatable {
    let id: String
    var originalText: String       // ASR result (English)
    var translatedText: String?    // Translation result (Chinese)
    var startTime: TimeInterval
    var endTime: TimeInterval
    var status: SegmentStatus
    var confidence: Double?        // ASR confidence score

    init(
        id: String = UUID().uuidString,
        originalText: String = "",
        translatedText: String? = nil,
        startTime: TimeInterval,
        endTime: TimeInterval,
        status: SegmentStatus = .transcribing,
        confidence: Double? = nil
    ) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.confidence = confidence
    }

    var duration: TimeInterval {
        endTime - startTime
    }

    var isProcessing: Bool {
        status == .transcribing || status == .translating
    }
}

// MARK: - Segment Status
enum SegmentStatus: String, Codable {
    case pending          // Waiting to be processed
    case transcribing     // ASR in progress
    case translating      // Translation in progress
    case completed        // Both ASR and translation done
    case failed           // Processing failed

    var displayText: String {
        switch self {
        case .pending: return "..."
        case .transcribing: return "Listening..."
        case .translating: return "Translating..."
        case .completed: return ""
        case .failed: return "Failed"
        }
    }

    var isComplete: Bool {
        self == .completed
    }
}

// MARK: - ASR Request/Response

struct ASRRequest: Codable {
    let audioBase64: String
    let audioFormat: String
    let startTime: Double
    let overlapDuration: Double?
    let languageHint: String?

    enum CodingKeys: String, CodingKey {
        case audioBase64 = "audio_base64"
        case audioFormat = "audio_format"
        case startTime = "start_time"
        case overlapDuration = "overlap_duration"
        case languageHint = "language_hint"
    }
}

struct ASRResponse: Codable {
    let text: String
    let confidence: Double?
    let words: [ASRWord]?
    let language: String?
    let detectedLanguage: String?

    enum CodingKeys: String, CodingKey {
        case text
        case confidence
        case words
        case language
        case detectedLanguage = "detected_language"
    }
}

// MARK: - Deduplication Request/Response

struct DeduplicateRequest: Codable {
    let previousText: String
    let previousEndTime: Double
    let currentText: String
    let currentStartTime: Double
    let overlapDuration: Double

    enum CodingKeys: String, CodingKey {
        case previousText = "previous_text"
        case previousEndTime = "previous_end_time"
        case currentText = "current_text"
        case currentStartTime = "current_start_time"
        case overlapDuration = "overlap_duration"
    }
}

struct DeduplicateResponse: Codable {
    let deduplicatedText: String
    let overlapText: String

    enum CodingKeys: String, CodingKey {
        case deduplicatedText = "deduplicated_text"
        case overlapText = "overlap_text"
    }
}

struct ASRWord: Codable {
    let word: String
    let start: Double
    let end: Double
    let confidence: Double?
}

// MARK: - Language Pair

struct LanguagePair: Equatable, Identifiable {
    var id: String { "\(source)-\(target)" }
    let source: String
    let target: String
    let sourceLabel: String
    let targetLabel: String

    static let englishToChinese = LanguagePair(
        source: "en-US",
        target: "zh-CN",
        sourceLabel: "English",
        targetLabel: "Chinese"
    )

    static let chineseToEnglish = LanguagePair(
        source: "zh-CN",
        target: "en-US",
        sourceLabel: "Chinese",
        targetLabel: "English"
    )

    static let japaneseToChinese = LanguagePair(
        source: "ja-JP",
        target: "zh-CN",
        sourceLabel: "Japanese",
        targetLabel: "Chinese"
    )

    static let japaneseToEnglish = LanguagePair(
        source: "ja-JP",
        target: "en-US",
        sourceLabel: "Japanese",
        targetLabel: "English"
    )

    static let chineseToJapanese = LanguagePair(
        source: "zh-CN",
        target: "ja-JP",
        sourceLabel: "Chinese",
        targetLabel: "Japanese"
    )

    static let englishToJapanese = LanguagePair(
        source: "en-US",
        target: "ja-JP",
        sourceLabel: "English",
        targetLabel: "Japanese"
    )

    static let all: [LanguagePair] = [
        .englishToChinese,
        .chineseToEnglish,
        .japaneseToChinese,
        .japaneseToEnglish,
        .chineseToJapanese,
        .englishToJapanese
    ]
}

// MARK: - Interpreter Error

enum InterpreterError: Error, LocalizedError {
    case microphonePermissionDenied
    case recordingFailed(String)
    case asrFailed(String)
    case translationFailed(String)
    case networkError(String)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Please allow microphone access in Settings"
        case .recordingFailed(let message):
            return "Recording failed: \(message)"
        case .asrFailed(let message):
            return "Speech recognition failed: \(message)"
        case .translationFailed(let message):
            return "Translation failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .notAuthenticated:
            return "Please sign in to use this feature"
        }
    }
}

// MARK: - Target Language

enum TargetLanguage: String, Codable, CaseIterable, Identifiable {
    case chinese = "zh"
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }

    var fullCode: String {
        switch self {
        case .chinese: return "zh-CN"
        case .english: return "en-US"
        case .japanese: return "ja-JP"
        }
    }
}

// MARK: - Interpreter Settings

struct InterpreterSettings: Codable {
    var targetLanguage: TargetLanguage
    var autoScroll: Bool
    var showConfidence: Bool
    var hapticFeedback: Bool

    static let `default` = InterpreterSettings(
        targetLanguage: .chinese,
        autoScroll: true,
        showConfidence: false,
        hapticFeedback: true
    )
}

// MARK: - History Manager

@MainActor
class InterpreterHistoryManager: ObservableObject {
    static let shared = InterpreterHistoryManager()

    @Published var sessions: [InterpreterSession] = []

    private let storageKey = "interpreter.history"
    private let maxSessions = 50

    private init() {
        load()
    }

    func save(_ session: InterpreterSession) {
        // Only save sessions with content
        guard !session.segments.isEmpty,
              session.segments.contains(where: { !$0.originalText.isEmpty }) else {
            return
        }

        // Insert at beginning
        sessions.insert(session, at: 0)

        // Limit history size
        if sessions.count > maxSessions {
            sessions = Array(sessions.prefix(maxSessions))
        }

        persist()
    }

    func delete(_ session: InterpreterSession) {
        sessions.removeAll { $0.id == session.id }
        persist()
    }

    func clearAll() {
        sessions.removeAll()
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([InterpreterSession].self, from: data) else {
            return
        }
        sessions = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
