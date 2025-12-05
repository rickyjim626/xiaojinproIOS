//
//  AIChatView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI
import PhotosUI

struct AIChatView: View {
    @ObservedObject var store: AIChatStore
    let initialConversation: AIConversation?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool

    @State private var showModelPicker = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            messagesView

            // Input Bar
            inputBar
        }
        .navigationTitle(store.currentConversation?.displayTitle ?? "新对话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                modelButton
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if store.isStreaming {
                        Button {
                            store.cancelGeneration()
                        } label: {
                            Label("停止生成", systemImage: "stop.circle")
                        }
                    }

                    if let lastMessage = store.messages.last, lastMessage.role == .assistant {
                        Button {
                            Task { await store.regenerateLastResponse() }
                        } label: {
                            Label("重新生成", systemImage: "arrow.clockwise")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        store.clearCurrentConversation()
                        dismiss()
                    } label: {
                        Label("清除对话", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            if let conversation = initialConversation {
                await store.selectConversation(conversation)
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(store: store)
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 5,
            matching: .images
        )
        .onChange(of: selectedPhotos) { _, newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        store.addImageAttachment(image)
                    }
                }
                selectedPhotos = []
            }
        }
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.pdf, .plainText, .json],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    if url.startAccessingSecurityScopedResource() {
                        store.addDocumentAttachment(url: url)
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            }
        }
    }

    // MARK: - Model Button

    private var modelButton: some View {
        Button {
            showModelPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.selectedModel.providerIcon)
                    .font(.caption)
                Text(store.selectedModel.displayName)
                    .font(.subheadline)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundColor(.primary)
        }
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if store.isLoadingMessages {
                        ProgressView()
                            .padding()
                    }

                    ForEach(store.messages) { message in
                        AIMessageBubble(message: message, isStreaming: store.isStreaming && message.id == store.messages.last?.id)
                            .id(message.id)
                    }

                    // Spacer for scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding()
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: store.messages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: store.streamingContent) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Pending attachments
            if !store.pendingAttachments.isEmpty {
                attachmentsPreview
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                // Attachment button
                Menu {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("选择图片", systemImage: "photo")
                    }

                    Button {
                        showDocumentPicker = true
                    } label: {
                        Label("选择文件", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }

                // Text input
                TextField("输入消息...", text: $store.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isInputFocused)

                // Send button
                Button {
                    Task { await store.sendMessage() }
                } label: {
                    Image(systemName: store.isSending || store.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(canSend ? .blue : .gray)
                }
                .disabled(!canSend && !store.isStreaming)
                .onTapGesture {
                    if store.isStreaming {
                        store.cancelGeneration()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
    }

    private var canSend: Bool {
        !store.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !store.pendingAttachments.isEmpty
    }

    // MARK: - Attachments Preview

    private var attachmentsPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.pendingAttachments) { attachment in
                    AttachmentPreviewCell(attachment: attachment) {
                        store.removeAttachment(attachment)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6))
    }
}

// MARK: - Message Bubble

struct AIMessageBubble: View {
    let message: AIMessage
    let isStreaming: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isAssistant {
                // AI Avatar
                Image(systemName: "sparkles")
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.purple)
                    .cornerRadius(16)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Attachments if any
                if message.hasAttachments {
                    attachmentsView
                }

                // Content
                Text(message.content.isEmpty && isStreaming ? "..." : message.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(message.isUser ? Color.blue : Color(.systemGray6))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(16)

                // Metadata
                if let tokens = message.completionTokens, tokens > 0 {
                    Text("\(tokens) tokens")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)

            if message.isUser {
                // User Avatar
                Image(systemName: "person.fill")
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.blue)
                    .cornerRadius(16)
            }
        }
    }

    @ViewBuilder
    private var attachmentsView: some View {
        let urls = message.attachmentUrls
        if !urls.isEmpty {
            HStack(spacing: 8) {
                ForEach(urls, id: \.self) { url in
                    if url.contains("image") || url.hasSuffix(".jpg") || url.hasSuffix(".png") {
                        AsyncImage(url: URL(string: url)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 100, height: 100)
                        .cornerRadius(8)
                    } else {
                        HStack {
                            Image(systemName: "doc")
                            Text("文件")
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
}

// MARK: - Attachment Preview Cell

struct AttachmentPreviewCell: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let thumbnail = attachment.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                VStack {
                    Image(systemName: attachment.icon)
                        .font(.title2)
                    Text(attachment.fileName)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .frame(width: 60, height: 60)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .offset(x: 6, y: -6)
        }
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    @ObservedObject var store: AIChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.availableModels) { model in
                    Button {
                        store.selectModel(model)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: model.providerIcon)
                                    Text(model.displayName)
                                        .fontWeight(.medium)
                                }

                                HStack(spacing: 8) {
                                    if model.capabilities?.supportsVision == true {
                                        Label("Vision", systemImage: "eye")
                                            .font(.caption2)
                                    }
                                    if model.isThinkingModel {
                                        Label("Thinking", systemImage: "brain")
                                            .font(.caption2)
                                    }
                                }
                                .foregroundColor(.secondary)
                            }

                            Spacer()

                            if model.id == store.selectedModel.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        AIChatView(store: AIChatStore(), initialConversation: nil)
    }
}
