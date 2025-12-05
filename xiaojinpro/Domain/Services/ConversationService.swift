//
//  ConversationService.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - Conversation Service
@MainActor
class ConversationService: ObservableObject {
    static let shared = ConversationService()

    @Published var conversations: [Conversation] = []
    @Published var isLoading = false

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Conversations CRUD

    func fetchConversations() async throws {
        isLoading = true
        defer { isLoading = false }

        let response: [Conversation] = try await apiClient.get(.conversations)
        conversations = response.sorted { $0.updatedAt > $1.updatedAt }
    }

    func createConversation(
        type: ConversationType = .chat,
        title: String? = nil,
        systemPrompt: String? = nil
    ) async throws -> Conversation {
        let request = CreateConversationRequest(
            type: type,
            title: title,
            systemPrompt: systemPrompt
        )

        let conversation: Conversation = try await apiClient.post(.conversations, body: request)
        conversations.insert(conversation, at: 0)
        return conversation
    }

    func deleteConversation(_ id: String) async throws {
        try await apiClient.delete(.conversation(id: id))
        conversations.removeAll { $0.id == id }
    }

    // MARK: - Messages

    func fetchMessages(conversationId: String, after: String? = nil) async throws -> [Message] {
        var queryItems: [URLQueryItem] = []
        if let after = after {
            queryItems.append(URLQueryItem(name: "after", value: after))
        }

        let response: MessagesResponse = try await apiClient.get(
            .conversationMessages(conversationId: conversationId),
            queryItems: queryItems
        )

        return response.messages
    }

    func sendMessage(
        conversationId: String,
        content: String,
        context: SendMessageRequest.MessageContext? = nil
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        let request = SendMessageRequest(content: content, context: context)

        return apiClient.stream(
            .conversationMessages(conversationId: conversationId),
            body: request
        )
    }
}

// MARK: - Conversation Store (for single conversation state)
@MainActor
class ConversationStore: ObservableObject {
    let conversation: Conversation

    @Published var messages: [Message] = []
    @Published var pendingMessage: Message?
    @Published var runningTasks: [XJPTask] = []
    @Published var isStreaming = false
    @Published var error: String?

    private let service = ConversationService.shared
    private var streamTask: Task<Void, Never>?

    init(conversation: Conversation) {
        self.conversation = conversation
    }

    func loadMessages() async {
        do {
            messages = try await service.fetchMessages(conversationId: conversation.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func send(_ content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isStreaming else { return }

        // Create pending user message
        let userMessage = Message(
            id: UUID().uuidString,
            conversationId: conversation.id,
            role: .user,
            content: content,
            toolCalls: nil,
            toolCallId: nil,
            createdAt: Date()
        )

        messages.append(userMessage)

        // Create pending assistant message
        pendingMessage = Message(
            id: UUID().uuidString,
            conversationId: conversation.id,
            role: .assistant,
            content: "",
            toolCalls: nil,
            toolCallId: nil,
            createdAt: Date()
        )

        isStreaming = true
        error = nil

        streamTask = Task {
            do {
                let stream = service.sendMessage(
                    conversationId: conversation.id,
                    content: content
                )

                for try await event in stream {
                    await handleStreamEvent(event)
                }

                // Finalize pending message
                if var pending = pendingMessage {
                    messages.append(pending)
                    pendingMessage = nil
                }
            } catch {
                self.error = error.localizedDescription
                pendingMessage = nil
            }

            isStreaming = false
            runningTasks.removeAll { $0.status.isTerminal }
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        pendingMessage = nil
    }

    private func handleStreamEvent(_ event: SSEEvent) async {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        switch event.event {
        case "text_delta":
            if let data = event.data.data(using: .utf8),
               let delta = try? decoder.decode(TextDeltaEvent.self, from: data) {
                pendingMessage?.content += delta.content
            }

        case "tool_call_started":
            if let data = event.data.data(using: .utf8),
               let started = try? decoder.decode(ToolCallStartedEvent.self, from: data) {
                let task = XJPTask(
                    id: started.taskId,
                    skillName: started.skill,
                    status: .running,
                    createdBy: nil,
                    createdFrom: .ios,
                    arguments: started.args,
                    result: nil,
                    error: nil,
                    progress: 0,
                    progressMessage: "开始执行...",
                    startedAt: Date(),
                    completedAt: nil,
                    createdAt: Date()
                )
                runningTasks.append(task)
            }

        case "tool_call_progress":
            if let data = event.data.data(using: .utf8),
               let progress = try? decoder.decode(ToolCallProgressEvent.self, from: data) {
                if let index = runningTasks.firstIndex(where: { $0.id == progress.taskId }) {
                    runningTasks[index].progress = progress.progress
                    runningTasks[index].progressMessage = progress.message
                }
            }

        case "tool_call_result":
            if let data = event.data.data(using: .utf8),
               let result = try? decoder.decode(ToolCallResultEvent.self, from: data) {
                if let index = runningTasks.firstIndex(where: { $0.id == result.taskId }) {
                    runningTasks[index].status = TaskStatus(rawValue: result.status) ?? .succeeded
                    runningTasks[index].result = result.result
                }
            }

        case "error":
            error = event.data

        case "done":
            break

        default:
            break
        }
    }
}
