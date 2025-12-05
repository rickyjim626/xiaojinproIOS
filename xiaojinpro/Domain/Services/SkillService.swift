//
//  SkillService.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - Skill Service
@MainActor
class SkillService: ObservableObject {
    static let shared = SkillService()

    @Published var skills: [Skill] = []
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Fetch Skills

    func fetchSkills() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: SkillsResponse = try await apiClient.get(.skills)
            skills = response.skills
        } catch {
            self.error = error.localizedDescription
        }
    }

    func skill(named name: String) -> Skill? {
        skills.first { $0.name == name }
    }

    func skills(for category: SkillCategory) -> [Skill] {
        skills.filter { $0.category == category }
    }

    var categories: [SkillCategory] {
        let usedCategories = Set(skills.map { $0.category })
        return SkillCategory.allCases.filter { usedCategories.contains($0) }
    }

    // MARK: - Execute Skill

    func executeSkill(
        name: String,
        arguments: [String: Any],
        conversationId: String? = nil
    ) async throws -> ExecuteSkillResponse {
        let request = ExecuteSkillRequest(arguments: arguments, conversationId: conversationId)
        return try await apiClient.post(.executeSkill(name: name), body: request)
    }

    // MARK: - Stream Skill Execution

    func executeSkillWithStream(
        name: String,
        arguments: [String: Any],
        conversationId: String? = nil
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        let request = ExecuteSkillRequest(arguments: arguments, conversationId: conversationId)
        return apiClient.stream(.executeSkill(name: name), body: request)
    }
}

// MARK: - Skill Executor (for single skill execution)
@MainActor
class SkillExecutor: ObservableObject {
    let skill: Skill

    @Published var arguments: [String: Any] = [:]
    @Published var task: XJPTask?
    @Published var isExecuting = false
    @Published var error: String?

    private let service = SkillService.shared
    private var streamTask: Task<Void, Never>?

    init(skill: Skill) {
        self.skill = skill
        setupDefaultArguments()
    }

    private func setupDefaultArguments() {
        guard let properties = skill.parameters.properties else { return }

        for (key, schema) in properties {
            if let defaultValue = schema.defaultValue {
                arguments[key] = defaultValue.value
            }
        }
    }

    func setArgument(_ key: String, value: Any?) {
        if let value = value {
            arguments[key] = value
        } else {
            arguments.removeValue(forKey: key)
        }
    }

    func validateArguments() -> [String] {
        var errors: [String] = []

        guard let required = skill.parameters.required else { return errors }

        for key in required {
            if arguments[key] == nil {
                let displayName = skill.parameters.properties?[key]?.description ?? key
                errors.append("请填写: \(displayName)")
            }
        }

        return errors
    }

    func execute(conversationId: String? = nil) async throws {
        let validationErrors = validateArguments()
        guard validationErrors.isEmpty else {
            throw SkillExecutionError.validationFailed(validationErrors)
        }

        isExecuting = true
        error = nil

        // Create initial task
        task = XJPTask(
            id: UUID().uuidString,
            skillName: skill.name,
            status: .pending,
            createdBy: nil,
            createdFrom: .ios,
            arguments: arguments.mapValues { AnyCodable($0) },
            result: nil,
            error: nil,
            progress: 0,
            progressMessage: nil,
            startedAt: nil,
            completedAt: nil,
            createdAt: Date()
        )

        do {
            let response = try await service.executeSkill(
                name: skill.name,
                arguments: arguments,
                conversationId: conversationId
            )

            task?.id = response.taskId
            task?.status = response.status

            // If not terminal, start polling or streaming
            if !response.status.isTerminal {
                await pollTaskStatus(taskId: response.taskId)
            }

        } catch {
            self.error = error.localizedDescription
            task?.status = .failed
            task?.error = error.localizedDescription
        }

        isExecuting = false
    }

    func executeWithStream(conversationId: String? = nil) {
        let validationErrors = validateArguments()
        guard validationErrors.isEmpty else {
            error = validationErrors.joined(separator: "\n")
            return
        }

        isExecuting = true
        error = nil

        task = XJPTask(
            id: UUID().uuidString,
            skillName: skill.name,
            status: .running,
            createdBy: nil,
            createdFrom: .ios,
            arguments: arguments.mapValues { AnyCodable($0) },
            result: nil,
            error: nil,
            progress: 0,
            progressMessage: "正在执行...",
            startedAt: Date(),
            completedAt: nil,
            createdAt: Date()
        )

        streamTask = Task {
            do {
                let stream = service.executeSkillWithStream(
                    name: skill.name,
                    arguments: arguments,
                    conversationId: conversationId
                )

                for try await event in stream {
                    await handleStreamEvent(event)
                }
            } catch {
                self.error = error.localizedDescription
                task?.status = .failed
                task?.error = error.localizedDescription
            }

            isExecuting = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isExecuting = false
        task?.status = .cancelled
    }

    private func handleStreamEvent(_ event: SSEEvent) async {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        switch event.event {
        case "tool_call_progress":
            if let data = event.data.data(using: .utf8),
               let progress = try? decoder.decode(ToolCallProgressEvent.self, from: data) {
                task?.progress = progress.progress
                task?.progressMessage = progress.message
            }

        case "tool_call_result":
            if let data = event.data.data(using: .utf8),
               let result = try? decoder.decode(ToolCallResultEvent.self, from: data) {
                task?.status = TaskStatus(rawValue: result.status) ?? .succeeded
                task?.result = result.result
            }

        case "error":
            error = event.data
            task?.status = .failed
            task?.error = event.data

        default:
            break
        }
    }

    private func pollTaskStatus(taskId: String) async {
        // Simple polling implementation
        // In production, use WebSocket or SSE
        for _ in 0..<60 { // Max 5 minutes (60 * 5s)
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

            do {
                let updatedTask: XJPTask = try await APIClient.shared.get(.task(id: taskId))
                task = updatedTask

                if updatedTask.status.isTerminal {
                    break
                }
            } catch {
                break
            }
        }
    }
}

// MARK: - Skill Execution Error
enum SkillExecutionError: LocalizedError {
    case validationFailed([String])
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .validationFailed(let errors):
            return errors.joined(separator: "\n")
        case .executionFailed(let message):
            return message
        }
    }
}
