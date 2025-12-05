//
//  TaskService.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - Task Service
@MainActor
class TaskService: ObservableObject {
    static let shared = TaskService()

    @Published var tasks: [XJPTask] = []
    @Published var isLoading = false
    @Published var error: String?

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Fetch Tasks

    func fetchTasks(filter: TaskFilter = TaskFilter()) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response: TasksResponse = try await apiClient.get(
                .tasks,
                queryItems: filter.queryItems
            )
            tasks = response.tasks
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fetchTask(id: String) async throws -> XJPTask {
        try await apiClient.get(.task(id: id))
    }

    // MARK: - Task Actions

    func cancelTask(id: String) async throws {
        let _: XJPTask = try await apiClient.post(
            .task(id: id),
            body: ["action": "cancel"]
        )

        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].status = .cancelled
        }
    }

    func retryTask(id: String) async throws -> XJPTask {
        try await apiClient.post(
            .task(id: id),
            body: ["action": "retry"]
        )
    }

    // MARK: - Task Events Stream

    func streamTaskEvents(taskId: String) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = APIConfig.Endpoint.taskEvents(id: taskId).url
                    let token = await AuthManager.shared.accessToken

                    let sseClient = SSEClient()
                    try await sseClient.connect(to: url, body: nil, token: token) { event in
                        continuation.yield(event)

                        if event.event == "done" || event.event == "completed" {
                            continuation.finish()
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Statistics

    var pendingCount: Int {
        tasks.filter { $0.status == .pending }.count
    }

    var runningCount: Int {
        tasks.filter { $0.status == .running }.count
    }

    var failedCount: Int {
        tasks.filter { $0.status == .failed }.count
    }

    var recentFailedTasks: [XJPTask] {
        tasks
            .filter { $0.status == .failed }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(10)
            .map { $0 }
    }

    func tasksBySkill() -> [String: [XJPTask]] {
        Dictionary(grouping: tasks) { $0.skillName }
    }
}
