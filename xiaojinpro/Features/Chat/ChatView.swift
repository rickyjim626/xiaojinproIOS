//
//  ChatView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI

struct ChatView: View {
    @StateObject var store: ConversationStore
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Pending message (streaming)
                        if let pending = store.pendingMessage {
                            MessageBubble(message: pending, isStreaming: true)
                                .id("pending")
                        }

                        // Running tasks
                        ForEach(store.runningTasks) { task in
                            TaskCardView(task: task)
                        }
                    }
                    .padding()
                }
                .onChange(of: store.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: store.pendingMessage?.content) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            // Error banner
            if let error = store.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button {
                        store.error = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            // Input bar
            ChatInputBar(
                text: $inputText,
                isStreaming: store.isStreaming,
                onSend: sendMessage,
                onCancel: store.cancel
            )
            .focused($isInputFocused)
        }
        .navigationTitle(store.conversation.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadMessages()
        }
    }

    private func sendMessage() {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        inputText = ""
        store.send(content)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if store.pendingMessage != nil {
                proxy.scrollTo("pending", anchor: .bottom)
            } else if let lastMessage = store.messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: Message
    var isStreaming: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isUser {
                Spacer(minLength: 60)
            }

            if !message.isUser {
                // AI Avatar
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "brain")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                    }
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Content
                Text(message.content.isEmpty && isStreaming ? "..." : message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isUser ? Color.blue : Color(.systemGray6))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(18)
                    .textSelection(.enabled)

                // Streaming indicator
                if isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("思考中...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Tool calls indicator
                if message.hasToolCalls {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption2)
                        Text("调用了 \(message.toolCalls!.count) 个工具")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }

            if message.isUser {
                // User Avatar
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                    }
            }

            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Chat Input Bar
struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Text input
            TextField("输入消息...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .lineLimit(1...5)
                .disabled(isStreaming)

            // Send/Cancel button
            Button {
                if isStreaming {
                    onCancel()
                } else {
                    onSend()
                }
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(isStreaming ? .red : (text.isEmpty ? .gray : .blue))
            }
            .disabled(!isStreaming && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Task Card View
struct TaskCardView: View {
    let task: XJPTask

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 40, height: 40)

                if task.status == .running {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: task.status.icon)
                        .foregroundColor(statusColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(task.skillName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let message = task.progressMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let progress = task.progress, task.status == .running {
                    ProgressView(value: Double(progress), total: 100)
                        .progressViewStyle(.linear)
                }
            }

            Spacer()

            if let duration = task.formattedDuration {
                Text(duration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var statusColor: Color {
        switch task.status {
        case .pending: return .gray
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(store: ConversationStore(conversation: Conversation(
            id: "test",
            tenantId: nil,
            type: .chat,
            title: "测试对话",
            systemPrompt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )))
    }
}
