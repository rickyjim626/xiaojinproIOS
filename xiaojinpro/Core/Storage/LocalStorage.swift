//
//  LocalStorage.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - Storage Keys
enum StorageKey: String {
    // User preferences
    case isDarkMode = "user.isDarkMode"
    case preferredLanguage = "user.preferredLanguage"
    case notificationsEnabled = "user.notificationsEnabled"

    // AI settings
    case defaultModel = "ai.defaultModel"
    case streamingEnabled = "ai.streamingEnabled"
    case maxTokens = "ai.maxTokens"

    // Cache
    case cachedConversations = "cache.conversations"
    case cachedSkills = "cache.skills"
    case lastSyncTime = "cache.lastSyncTime"

    // App state
    case lastViewedConversationId = "app.lastViewedConversationId"
    case onboardingCompleted = "app.onboardingCompleted"
    case appVersion = "app.version"
}

// MARK: - Local Storage
@MainActor
class LocalStorage: ObservableObject {
    static let shared = LocalStorage()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - User Preferences

    @Published var isDarkMode: Bool {
        didSet { defaults.set(isDarkMode, forKey: StorageKey.isDarkMode.rawValue) }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: StorageKey.notificationsEnabled.rawValue) }
    }

    @Published var preferredLanguage: String {
        didSet { defaults.set(preferredLanguage, forKey: StorageKey.preferredLanguage.rawValue) }
    }

    // MARK: - AI Settings

    @Published var defaultModel: String {
        didSet { defaults.set(defaultModel, forKey: StorageKey.defaultModel.rawValue) }
    }

    @Published var streamingEnabled: Bool {
        didSet { defaults.set(streamingEnabled, forKey: StorageKey.streamingEnabled.rawValue) }
    }

    @Published var maxTokens: Int {
        didSet { defaults.set(maxTokens, forKey: StorageKey.maxTokens.rawValue) }
    }

    // MARK: - App State

    var lastViewedConversationId: String? {
        get { defaults.string(forKey: StorageKey.lastViewedConversationId.rawValue) }
        set { defaults.set(newValue, forKey: StorageKey.lastViewedConversationId.rawValue) }
    }

    var onboardingCompleted: Bool {
        get { defaults.bool(forKey: StorageKey.onboardingCompleted.rawValue) }
        set { defaults.set(newValue, forKey: StorageKey.onboardingCompleted.rawValue) }
    }

    // MARK: - Initialization

    private init() {
        // Load saved values or use defaults
        self.isDarkMode = defaults.object(forKey: StorageKey.isDarkMode.rawValue) as? Bool ?? false
        self.notificationsEnabled = defaults.object(forKey: StorageKey.notificationsEnabled.rawValue) as? Bool ?? true
        self.preferredLanguage = defaults.string(forKey: StorageKey.preferredLanguage.rawValue) ?? "zh-Hans"
        self.defaultModel = defaults.string(forKey: StorageKey.defaultModel.rawValue) ?? "claude-sonnet-4-20250514"
        self.streamingEnabled = defaults.object(forKey: StorageKey.streamingEnabled.rawValue) as? Bool ?? true
        self.maxTokens = defaults.object(forKey: StorageKey.maxTokens.rawValue) as? Int ?? 4096
    }

    // MARK: - Generic Storage Methods

    func save<T: Encodable>(_ value: T, forKey key: StorageKey) {
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key.rawValue)
        }
    }

    func load<T: Decodable>(_ type: T.Type, forKey key: StorageKey) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func remove(forKey key: StorageKey) {
        defaults.removeObject(forKey: key.rawValue)
    }

    // MARK: - Cache Management

    var lastSyncTime: Date? {
        get { defaults.object(forKey: StorageKey.lastSyncTime.rawValue) as? Date }
        set { defaults.set(newValue, forKey: StorageKey.lastSyncTime.rawValue) }
    }

    func cacheConversations(_ conversations: [Conversation]) {
        save(conversations, forKey: .cachedConversations)
        lastSyncTime = Date()
    }

    func getCachedConversations() -> [Conversation]? {
        load([Conversation].self, forKey: .cachedConversations)
    }

    func cacheSkills(_ skills: [Skill]) {
        save(skills, forKey: .cachedSkills)
    }

    func getCachedSkills() -> [Skill]? {
        load([Skill].self, forKey: .cachedSkills)
    }

    func clearCache() {
        remove(forKey: .cachedConversations)
        remove(forKey: .cachedSkills)
        lastSyncTime = nil
    }

    func isCacheStale(maxAge: TimeInterval = 300) -> Bool {
        guard let lastSync = lastSyncTime else { return true }
        return Date().timeIntervalSince(lastSync) > maxAge
    }

    // MARK: - Reset

    func resetToDefaults() {
        isDarkMode = false
        notificationsEnabled = true
        preferredLanguage = "zh-Hans"
        defaultModel = "claude-sonnet-4-20250514"
        streamingEnabled = true
        maxTokens = 4096
        clearCache()
    }
}

// MARK: - Offline Queue Manager
@MainActor
class OfflineQueueManager: ObservableObject {
    static let shared = OfflineQueueManager()

    @Published private(set) var pendingActions: [PendingAction] = []
    @Published private(set) var isSyncing = false

    private let storageKey = "offline.pendingActions"
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        loadPendingActions()
    }

    // MARK: - Queue Management

    func enqueue(_ action: PendingAction) {
        pendingActions.append(action)
        savePendingActions()
    }

    func dequeue(_ action: PendingAction) {
        pendingActions.removeAll { $0.id == action.id }
        savePendingActions()
    }

    func clearQueue() {
        pendingActions.removeAll()
        savePendingActions()
    }

    // MARK: - Sync

    func syncPendingActions() async {
        guard !isSyncing, !pendingActions.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        var successfulActions: [PendingAction] = []

        for action in pendingActions {
            do {
                try await executeAction(action)
                successfulActions.append(action)
            } catch {
                print("Failed to sync action \(action.id): \(error)")
                // Keep failed actions in queue for retry
            }
        }

        // Remove successful actions
        for action in successfulActions {
            dequeue(action)
        }
    }

    private func executeAction(_ action: PendingAction) async throws {
        switch action.type {
        case .sendMessage:
            guard let conversationId = action.payload["conversationId"] as? String,
                  let content = action.payload["content"] as? String else {
                throw OfflineError.invalidPayload
            }
            let request = SendMessageRequest(content: content, context: nil)
            let _: Message = try await APIClient.shared.post(
                .conversationMessages(conversationId: conversationId),
                body: request
            )

        case .createConversation:
            guard let title = action.payload["title"] as? String else {
                throw OfflineError.invalidPayload
            }
            let request = CreateConversationRequest(
                type: .chat,
                title: title,
                systemPrompt: action.payload["systemPrompt"] as? String
            )
            let _: Conversation = try await APIClient.shared.post(.conversations, body: request)

        case .executeSkill:
            guard let skillName = action.payload["skillName"] as? String,
                  let arguments = action.payload["arguments"] as? [String: Any] else {
                throw OfflineError.invalidPayload
            }
            let request = ExecuteSkillRequest(arguments: arguments, conversationId: nil)
            let _: ExecuteSkillResponse = try await APIClient.shared.post(
                .executeSkill(name: skillName),
                body: request
            )
        }
    }

    // MARK: - Persistence

    private func savePendingActions() {
        if let data = try? encoder.encode(pendingActions) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func loadPendingActions() {
        guard let data = defaults.data(forKey: storageKey),
              let actions = try? decoder.decode([PendingAction].self, from: data) else {
            return
        }
        pendingActions = actions
    }
}

// MARK: - Pending Action
struct PendingAction: Codable, Identifiable {
    let id: String
    let type: ActionType
    let payload: [String: AnyCodable]
    let createdAt: Date
    var retryCount: Int

    enum ActionType: String, Codable {
        case sendMessage
        case createConversation
        case executeSkill
    }

    init(type: ActionType, payload: [String: Any]) {
        self.id = UUID().uuidString
        self.type = type
        self.payload = payload.mapValues { AnyCodable($0) }
        self.createdAt = Date()
        self.retryCount = 0
    }
}

// MARK: - Offline Error
enum OfflineError: Error, LocalizedError {
    case invalidPayload
    case syncFailed

    var errorDescription: String? {
        switch self {
        case .invalidPayload: return "Invalid action payload"
        case .syncFailed: return "Failed to sync offline actions"
        }
    }
}
