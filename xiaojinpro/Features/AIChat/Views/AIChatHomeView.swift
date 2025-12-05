//
//  AIChatHomeView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI

struct AIChatHomeView: View {
    @StateObject private var store = AIChatStore()
    @State private var searchText = ""
    @State private var showNewChat = false
    @State private var showSettings = false
    @State private var selectedConversation: AIConversation?

    var filteredConversations: [AIConversation] {
        if searchText.isEmpty {
            return store.conversations
        }
        return store.conversations.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.conversations.isEmpty && !store.isLoadingConversations {
                    emptyStateView
                } else {
                    conversationsList
                }
            }
            .navigationTitle("AI 助手")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }

                        Button {
                            startNewChat()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索对话...")
            .refreshable {
                await store.loadConversations(refresh: true)
            }
            .task {
                await store.loadConversations(refresh: true)
                await store.loadModels()
            }
            .navigationDestination(item: $selectedConversation) { conversation in
                AIChatView(store: store, initialConversation: conversation)
            }
            .navigationDestination(isPresented: $showNewChat) {
                AIChatView(store: store, initialConversation: nil)
            }
            .sheet(isPresented: $showSettings) {
                AIChatSettingsView(store: store)
            }
            .alert("错误", isPresented: .init(
                get: { store.error != nil },
                set: { if !$0 { store.error = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(store.error ?? "")
            }
        }
        .environmentObject(store)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("开始新对话")
                .font(.title2)
                .fontWeight(.medium)

            Text("点击右上角 + 开始与 AI 助手对话")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                startNewChat()
            } label: {
                Label("新建对话", systemImage: "plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top, 10)
        }
        .padding()
    }

    // MARK: - Conversations List

    private var conversationsList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                AIConversationRow(conversation: conversation)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectConversation(conversation)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                await store.deleteConversation(conversation)
                            }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }

                        Button {
                            Task {
                                await store.archiveConversation(conversation)
                            }
                        } label: {
                            Label("归档", systemImage: "archivebox")
                        }
                        .tint(.orange)
                    }
            }

            if store.hasMoreConversations {
                HStack {
                    Spacer()
                    ProgressView()
                        .onAppear {
                            Task {
                                await store.loadConversations(refresh: false)
                            }
                        }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func startNewChat() {
        store.clearCurrentConversation()
        showNewChat = true
    }

    private func selectConversation(_ conversation: AIConversation) {
        Task {
            await store.selectConversation(conversation)
            selectedConversation = conversation
        }
    }
}

// MARK: - AI Conversation Row

struct AIConversationRow: View {
    let conversation: AIConversation

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconForModel(conversation.model))
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(modelDisplayName(conversation.model))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text("\(conversation.messageCount)条")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text(conversation.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func iconForModel(_ model: String) -> String {
        if model.contains("claude") {
            return "sparkles"
        } else if model.contains("gemini") {
            return "globe"
        } else {
            return "brain"
        }
    }

    private func modelDisplayName(_ model: String) -> String {
        switch model {
        case "claude-sonnet-4.5": return "Claude 4.5"
        case "claude-sonnet-4.5-thinking": return "Claude 4.5 Thinking"
        case "claude-opus-4.1": return "Opus 4.1"
        case "claude-opus-4.1-thinking": return "Opus 4.1 Thinking"
        case "gemini-3-pro-preview": return "Gemini 3"
        default: return model
        }
    }
}

// MARK: - Settings View

struct AIChatSettingsView: View {
    @ObservedObject var store: AIChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("默认模型") {
                    Picker("AI 模型", selection: $store.selectedModel) {
                        ForEach(store.availableModels) { model in
                            HStack {
                                Image(systemName: model.providerIcon)
                                Text(model.displayName)
                            }
                            .tag(model)
                        }
                    }
                }

                Section("生成设置") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.1f", store.temperature))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $store.temperature, in: 0...2, step: 0.1)
                    }
                }

                Section("系统提示词") {
                    TextEditor(text: $store.systemPrompt)
                        .frame(minHeight: 100)
                }

                Section {
                    Text("Temperature 越高，回复越有创意但可能不太准确。\n建议一般对话使用 0.7，创意写作使用 1.0。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("AI 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    AIChatHomeView()
}
