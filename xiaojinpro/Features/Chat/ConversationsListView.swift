//
//  ConversationsListView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI

struct ConversationsListView: View {
    @StateObject private var service = ConversationService.shared
    @State private var showingNewConversation = false
    @State private var selectedConversation: Conversation?

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.conversations.isEmpty {
                    LoadingView()
                } else if service.conversations.isEmpty {
                    EmptyStateView(
                        icon: "bubble.left.and.bubble.right",
                        title: "暂无对话",
                        message: "开始一个新对话，与 AI 助手交流",
                        action: { showingNewConversation = true },
                        actionTitle: "新建对话"
                    )
                } else {
                    conversationsList
                }
            }
            .navigationTitle("对话")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewConversation = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                try? await service.fetchConversations()
            }
            .sheet(isPresented: $showingNewConversation) {
                NewConversationSheet { conversation in
                    selectedConversation = conversation
                }
            }
            .navigationDestination(item: $selectedConversation) { conversation in
                ChatView(store: ConversationStore(conversation: conversation))
            }
        }
        .task {
            try? await service.fetchConversations()
        }
    }

    private var conversationsList: some View {
        List {
            ForEach(service.conversations) { conversation in
                ConversationRow(conversation: conversation)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedConversation = conversation
                    }
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.insetGrouped)
    }

    private func deleteConversations(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let conversation = service.conversations[index]
                try? await service.deleteConversation(conversation.id)
            }
        }
    }
}

// MARK: - Conversation Row
struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            ZStack {
                Circle()
                    .fill(typeColor.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: conversation.type.icon)
                    .foregroundColor(typeColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(conversation.type.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formattedDate)
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

    private var typeColor: Color {
        switch conversation.type {
        case .chat: return .blue
        case .admin: return .red
        case .workflow: return .purple
        }
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: conversation.updatedAt, relativeTo: Date())
    }
}

// MARK: - New Conversation Sheet
struct NewConversationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedType: ConversationType = .chat
    @State private var isCreating = false

    let onCreated: (Conversation) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("对话标题（可选）", text: $title)
                }

                Section("对话类型") {
                    Picker("类型", selection: $selectedType) {
                        ForEach(ConversationType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Text(typeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("新建对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        createConversation()
                    }
                    .disabled(isCreating)
                }
            }
        }
    }

    private var typeDescription: String {
        switch selectedType {
        case .chat:
            return "普通对话模式，可以与 AI 助手进行多轮交流，支持工具调用。"
        case .admin:
            return "管理模式，可以通过自然语言管理服务、查看状态、修改配置。需要管理员权限。"
        case .workflow:
            return "工作流模式，适合执行复杂的多步骤任务。"
        }
    }

    private func createConversation() {
        isCreating = true

        Task {
            do {
                let conversation = try await ConversationService.shared.createConversation(
                    type: selectedType,
                    title: title.isEmpty ? nil : title,
                    systemPrompt: selectedType == .admin ? adminSystemPrompt : nil
                )
                dismiss()
                onCreated(conversation)
            } catch {
                isCreating = false
            }
        }
    }

    private var adminSystemPrompt: String {
        """
        你是 xiaojinpro 宇宙的管理助手。你可以帮助用户：
        - 查看和管理服务状态
        - 查询任务队列和失败记录
        - 调整系统配置
        - 查看 AI 使用统计
        请使用提供的工具来执行管理操作。
        """
    }
}

#Preview {
    ConversationsListView()
}
