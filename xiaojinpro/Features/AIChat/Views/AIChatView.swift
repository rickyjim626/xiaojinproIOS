//
//  AIChatView.swift
//  xiaojinpro
//
//  Claude-style AI Chat View
//

import SwiftUI
import PhotosUI

// MARK: - Chat Theme

final class ChatTheme: ObservableObject, @unchecked Sendable {

    let colors: Colors
    let typography: Typography
    let dimensions: Dimensions

    init(
        colors: Colors = .init(),
        typography: Typography = .init(),
        dimensions: Dimensions = .init()
    ) {
        self.colors = colors
        self.typography = typography
        self.dimensions = dimensions
    }

    struct Colors {
        let background: Color
        let secondaryBackground: Color
        let userBubble: Color
        let userText: Color
        let assistantBubble: Color
        let assistantText: Color
        let assistantAvatar: Color
        let userAvatar: Color
        let inputBackground: Color
        let inputBorder: Color
        let inputText: Color
        let accent: Color
        let sendButton: Color
        let sendButtonDisabled: Color
        let timestamp: Color
        let tokenCount: Color

        init(
            background: Color = Color(.systemBackground),
            secondaryBackground: Color = Color(.secondarySystemBackground),
            userBubble: Color = Color.blue,
            userText: Color = .white,
            assistantBubble: Color = Color(.systemGray6),
            assistantText: Color = Color(.label),
            assistantAvatar: Color = Color(red: 0.85, green: 0.65, blue: 0.45),
            userAvatar: Color = .blue,
            inputBackground: Color = Color(.systemGray6),
            inputBorder: Color = Color(.systemGray4),
            inputText: Color = Color(.label),
            accent: Color = .blue,
            sendButton: Color = .blue,
            sendButtonDisabled: Color = Color(.systemGray3),
            timestamp: Color = Color(.secondaryLabel),
            tokenCount: Color = Color(.tertiaryLabel)
        ) {
            self.background = background
            self.secondaryBackground = secondaryBackground
            self.userBubble = userBubble
            self.userText = userText
            self.assistantBubble = assistantBubble
            self.assistantText = assistantText
            self.assistantAvatar = assistantAvatar
            self.userAvatar = userAvatar
            self.inputBackground = inputBackground
            self.inputBorder = inputBorder
            self.inputText = inputText
            self.accent = accent
            self.sendButton = sendButton
            self.sendButtonDisabled = sendButtonDisabled
            self.timestamp = timestamp
            self.tokenCount = tokenCount
        }
    }

    struct Typography {
        let messageFont: Font
        let timestampFont: Font
        let inputFont: Font

        init(
            messageFont: Font = .body,
            timestampFont: Font = .caption2,
            inputFont: Font = .body
        ) {
            self.messageFont = messageFont
            self.timestampFont = timestampFont
            self.inputFont = inputFont
        }
    }

    struct Dimensions {
        let bubbleCornerRadius: CGFloat
        let bubblePadding: EdgeInsets
        let bubbleMaxWidthRatio: CGFloat
        let avatarSize: CGFloat
        let inputCornerRadius: CGFloat
        let messageSpacing: CGFloat
        let avatarMessageSpacing: CGFloat
        let contentPadding: EdgeInsets

        init(
            bubbleCornerRadius: CGFloat = 18,
            bubblePadding: EdgeInsets = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14),
            bubbleMaxWidthRatio: CGFloat = 0.78,
            avatarSize: CGFloat = 28,
            inputCornerRadius: CGFloat = 22,
            messageSpacing: CGFloat = 12,
            avatarMessageSpacing: CGFloat = 8,
            contentPadding: EdgeInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        ) {
            self.bubbleCornerRadius = bubbleCornerRadius
            self.bubblePadding = bubblePadding
            self.bubbleMaxWidthRatio = bubbleMaxWidthRatio
            self.avatarSize = avatarSize
            self.inputCornerRadius = inputCornerRadius
            self.messageSpacing = messageSpacing
            self.avatarMessageSpacing = avatarMessageSpacing
            self.contentPadding = contentPadding
        }
    }

    // Preset themes
    static let claudeLight = ChatTheme(
        colors: Colors(
            userBubble: Color(red: 0.9, green: 0.88, blue: 0.85),
            userText: Color(.label),
            assistantBubble: .clear,
            assistantAvatar: Color(red: 0.85, green: 0.65, blue: 0.45),
            userAvatar: Color(red: 0.4, green: 0.4, blue: 0.45)
        ),
        dimensions: Dimensions(bubbleCornerRadius: 20)
    )

    static let claudeDark = ChatTheme(
        colors: Colors(
            background: Color(red: 0.12, green: 0.12, blue: 0.14),
            secondaryBackground: Color(red: 0.18, green: 0.18, blue: 0.2),
            userBubble: Color(red: 0.25, green: 0.25, blue: 0.28),
            userText: .white,
            assistantBubble: .clear,
            assistantText: Color(white: 0.92),
            assistantAvatar: Color(red: 0.85, green: 0.65, blue: 0.45),
            userAvatar: Color(red: 0.5, green: 0.5, blue: 0.55),
            inputBackground: Color(red: 0.2, green: 0.2, blue: 0.22),
            inputBorder: Color(red: 0.3, green: 0.3, blue: 0.32)
        ),
        dimensions: Dimensions(bubbleCornerRadius: 20)
    )
}

// MARK: - Environment Key

private struct ChatThemeKey: EnvironmentKey {
    static let defaultValue = ChatTheme()
}

extension EnvironmentValues {
    var chatTheme: ChatTheme {
        get { self[ChatThemeKey.self] }
        set { self[ChatThemeKey.self] = newValue }
    }
}

extension View {
    func chatTheme(_ theme: ChatTheme) -> some View {
        environment(\.chatTheme, theme)
    }
}

// MARK: - AI Chat View

struct AIChatView: View {
    @ObservedObject var store: AIChatStore
    let initialConversation: AIConversation?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var showModelPicker = false
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    private var theme: ChatTheme {
        colorScheme == .dark ? .claudeDark : .claudeLight
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesView
            inputBar
        }
        .background(theme.colors.background)
        .navigationTitle(store.currentConversation?.displayTitle ?? "New Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                modelButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                menuButton
            }
        }
        .task {
            if let conversation = initialConversation {
                await store.selectConversation(conversation)
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(store: store, theme: theme)
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
            HStack(spacing: 6) {
                Image(systemName: store.selectedModel.providerIcon)
                    .font(.system(size: 12, weight: .medium))
                Text(store.selectedModel.displayName)
                    .font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.colors.secondaryBackground)
            .clipShape(Capsule())
        }
    }

    // MARK: - Menu Button

    private var menuButton: some View {
        Menu {
            if store.isStreaming {
                Button {
                    store.cancelGeneration()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
            }

            if let lastMessage = store.messages.last, lastMessage.role == .assistant {
                Button {
                    Task { await store.regenerateLastResponse() }
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }

            Divider()

            Button(role: .destructive) {
                store.clearCurrentConversation()
                dismiss()
            } label: {
                Label("Clear Chat", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: theme.dimensions.messageSpacing) {
                    if store.isLoadingMessages {
                        ProgressView()
                            .padding(.vertical, 40)
                    }

                    if store.messages.isEmpty && !store.isLoadingMessages {
                        welcomeView
                    }

                    ForEach(store.messages) { message in
                        ChatMessageBubble(
                            message: message,
                            isStreaming: store.isStreaming && message.id == store.messages.last?.id,
                            theme: theme,
                            isLastAssistantMessage: message.role == .assistant && message.id == store.messages.last?.id,
                            onRegenerate: {
                                await store.regenerateLastResponse()
                            },
                            onDelete: message.role == .user ? {
                                await store.deleteMessage(message)
                            } : nil
                        )
                        .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, theme.dimensions.contentPadding.top)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: store.streamingContent) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.colors.assistantAvatar,
                                theme.colors.assistantAvatar.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text("How can I help you?")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Ask me anything or start a conversation")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 60)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if !store.pendingAttachments.isEmpty {
                attachmentsPreview
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                Menu {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showDocumentPicker = true
                    } label: {
                        Label("Files", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(theme.colors.accent)
                        .symbolRenderingMode(.hierarchical)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $store.inputText, axis: .vertical)
                        .font(theme.typography.inputFont)
                        .foregroundColor(theme.colors.inputText)
                        .lineLimit(1...6)
                        .disabled(store.isSending || store.isStreaming)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.colors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: theme.dimensions.inputCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.dimensions.inputCornerRadius)
                        .stroke(theme.colors.inputBorder, lineWidth: 1)
                )

                if store.isStreaming {
                    Button {
                        store.cancelGeneration()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                    }
                } else {
                    Button {
                        Task { await store.sendMessage() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(canSend ? theme.colors.sendButton : theme.colors.sendButtonDisabled)
                    }
                    .disabled(!canSend || store.isSending)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(theme.colors.background)
        }
    }

    private var canSend: Bool {
        !store.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !store.pendingAttachments.isEmpty
    }

    private var attachmentsPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.pendingAttachments) { attachment in
                    AttachmentPreviewCell(attachment: attachment, theme: theme) {
                        store.removeAttachment(attachment)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(theme.colors.secondaryBackground)
    }
}

// MARK: - Chat Message Bubble

struct ChatMessageBubble: View {
    let message: AIMessage
    let isStreaming: Bool
    let theme: ChatTheme
    let isLastAssistantMessage: Bool
    var onRegenerate: (() async -> Void)?
    var onDelete: (() async -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: theme.dimensions.avatarMessageSpacing) {
            if message.isAssistant {
                assistantAvatar
            } else {
                Spacer(minLength: 48)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                if message.hasAttachments {
                    attachmentsView
                }

                messageContent

                if !isStreaming {
                    metadataView
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * theme.dimensions.bubbleMaxWidthRatio,
                   alignment: message.isUser ? .trailing : .leading)

            if message.isUser {
                userAvatar
            } else {
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal, theme.dimensions.contentPadding.leading)
    }

    private var assistantAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            theme.colors.assistantAvatar,
                            theme.colors.assistantAvatar.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: theme.dimensions.avatarSize, height: theme.dimensions.avatarSize)
    }

    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(theme.colors.userAvatar)

            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .frame(width: theme.dimensions.avatarSize, height: theme.dimensions.avatarSize)
    }

    @ViewBuilder
    private var messageContent: some View {
        let content = message.content.isEmpty && isStreaming ? "..." : message.content

        if message.isUser {
            Text(content)
                .textSelection(.enabled)
                .font(theme.typography.messageFont)
                .foregroundColor(theme.colors.userText)
                .padding(theme.dimensions.bubblePadding)
                .background(theme.colors.userBubble)
                .clipShape(RoundedRectangle(cornerRadius: theme.dimensions.bubbleCornerRadius))
                .contextMenu {
                    userContextMenu
                }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                MarkdownContentView(content: content, theme: theme)

                if isStreaming {
                    TypingIndicator()
                        .padding(.top, 4)
                }
            }
            .padding(theme.dimensions.bubblePadding)
            .background(theme.colors.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: theme.dimensions.bubbleCornerRadius))
            .contextMenu {
                assistantContextMenu
            }
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private var userContextMenu: some View {
        Button {
            UIPasteboard.general.string = message.content
            HapticManager.shared.notification(.success)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        if let onDelete = onDelete {
            Divider()
            Button(role: .destructive) {
                Task { await onDelete() }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var assistantContextMenu: some View {
        Button {
            UIPasteboard.general.string = message.content
            HapticManager.shared.notification(.success)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        if isLastAssistantMessage, let onRegenerate = onRegenerate {
            Button {
                Task { await onRegenerate() }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private var attachmentsView: some View {
        if let parts = message.contentParts {
            HStack(spacing: 8) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    attachmentView(for: part)
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentView(for part: AIContentPart) -> some View {
        switch part {
        case .imageUrl(let url):
            if url.hasPrefix("attachment://") {
                VStack {
                    Image(systemName: "photo.fill")
                        .font(.title2)
                        .foregroundColor(theme.colors.accent)
                    Text("Image")
                        .font(.caption2)
                        .foregroundColor(theme.colors.timestamp)
                }
                .frame(width: 70, height: 70)
                .background(theme.colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case .videoUrl:
            VStack {
                Image(systemName: "video.fill")
                    .font(.title2)
                    .foregroundColor(theme.colors.accent)
                Text("Video")
                    .font(.caption2)
                    .foregroundColor(theme.colors.timestamp)
            }
            .frame(width: 70, height: 70)
            .background(theme.colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        case .fileUrl(_, let mimeType):
            VStack {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundColor(theme.colors.accent)
                Text(mimeType ?? "File")
                    .font(.caption2)
                    .foregroundColor(theme.colors.timestamp)
                    .lineLimit(1)
            }
            .frame(width: 70, height: 70)
            .background(theme.colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        case .text:
            EmptyView()
        }
    }

    @ViewBuilder
    private var metadataView: some View {
        HStack(spacing: 8) {
            if let tokens = message.completionTokens, tokens > 0 {
                Text("\(tokens) tokens")
                    .font(theme.typography.timestampFont)
                    .foregroundColor(theme.colors.tokenCount)
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: animationPhase
                    )
            }
        }
        .onAppear {
            withAnimation {
                animationPhase = 2
            }
        }
    }
}

// MARK: - Attachment Preview Cell

struct AttachmentPreviewCell: View {
    let attachment: PendingAttachment
    let theme: ChatTheme
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail = attachment.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: attachment.icon)
                            .font(.title2)
                            .foregroundColor(theme.colors.accent)
                        Text(attachment.fileName)
                            .font(.caption2)
                            .foregroundColor(theme.colors.timestamp)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.colors.secondaryBackground)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .offset(x: 6, y: -6)
        }
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    @ObservedObject var store: AIChatStore
    let theme: ChatTheme
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
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: model.providerIcon)
                                        .foregroundColor(theme.colors.accent)
                                    Text(model.displayName)
                                        .fontWeight(.medium)
                                }

                                HStack(spacing: 12) {
                                    if model.capabilities?.supportsVision == true {
                                        Label("Vision", systemImage: "eye")
                                            .font(.caption)
                                    }
                                    if model.isThinkingModel {
                                        Label("Thinking", systemImage: "brain")
                                            .font(.caption)
                                    }
                                }
                                .foregroundColor(.secondary)
                            }

                            Spacer()

                            if model.id == store.selectedModel.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(theme.colors.accent)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Haptic Manager

final class HapticManager {
    static let shared = HapticManager()

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        // Pre-warm generators for faster response
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light: impactLight.impactOccurred()
        case .medium: impactMedium.impactOccurred()
        case .heavy: impactHeavy.impactOccurred()
        case .soft: impactSoft.impactOccurred()
        case .rigid: impactHeavy.impactOccurred()
        @unknown default: impactMedium.impactOccurred()
        }
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
    }
}

// MARK: - Markdown Content View

struct MarkdownContentView: View {
    let content: String
    let theme: ChatTheme

    var body: some View {
        let blocks = parseMarkdownBlocks(content)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks.indices, id: \.self) { index in
                switch blocks[index] {
                case .text(let text):
                    Text(parseInlineMarkdown(text))
                        .textSelection(.enabled)
                        .font(theme.typography.messageFont)
                        .foregroundColor(theme.colors.assistantText)
                case .code(let code, let language):
                    CodeBlockView(code: code, language: language)
                }
            }
        }
    }

    // Parse markdown into blocks (text or code)
    private func parseMarkdownBlocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [.text(text)]
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        var lastEnd = 0
        for match in matches {
            // Add text before code block
            if match.range.location > lastEnd {
                let textRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let textContent = nsString.substring(with: textRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !textContent.isEmpty {
                    blocks.append(.text(textContent))
                }
            }

            // Add code block
            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            let language = languageRange.length > 0 ? nsString.substring(with: languageRange) : nil
            let code = nsString.substring(with: codeRange)
            blocks.append(.code(code, language: language))

            lastEnd = match.range.location + match.range.length
        }

        // Add remaining text
        if lastEnd < nsString.length {
            let remainingText = nsString.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainingText.isEmpty {
                blocks.append(.text(remainingText))
            }
        }

        return blocks.isEmpty ? [.text(text)] : blocks
    }

    // Parse inline markdown (bold, italic, inline code)
    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        var result = text

        // Simple inline markdown parsing using NSRegularExpression
        // Parse inline code `code` -> keep code, mark with special char
        result = parsePattern(result, pattern: "`([^`]+)`") { code in
            "⟨CODE⟩\(code)⟨/CODE⟩"
        }

        // Parse bold **text**
        result = parsePattern(result, pattern: "\\*\\*([^*]+)\\*\\*") { boldText in
            "⟨BOLD⟩\(boldText)⟨/BOLD⟩"
        }

        // Parse italic *text* (but not ** which is bold)
        result = parsePattern(result, pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)") { italicText in
            "⟨ITALIC⟩\(italicText)⟨/ITALIC⟩"
        }

        // Build attributed string from marked text
        return buildAttributedString(from: result)
    }

    private func parsePattern(_ text: String, pattern: String, replacement: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        var result = text
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            if match.numberOfRanges >= 2 {
                let captureRange = match.range(at: 1)
                let captured = nsString.substring(with: captureRange)
                let fullRange = match.range
                let startIndex = result.index(result.startIndex, offsetBy: fullRange.location)
                let endIndex = result.index(startIndex, offsetBy: fullRange.length)
                result.replaceSubrange(startIndex..<endIndex, with: replacement(captured))
            }
        }

        return result
    }

    private func buildAttributedString(from text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text

        while !remaining.isEmpty {
            if let codeStart = remaining.range(of: "⟨CODE⟩"),
               let codeEnd = remaining.range(of: "⟨/CODE⟩") {
                // Add text before code
                let beforeText = String(remaining[remaining.startIndex..<codeStart.lowerBound])
                result.append(buildPlainAttributedString(from: beforeText))

                // Add code
                let codeText = String(remaining[codeStart.upperBound..<codeEnd.lowerBound])
                var codeAttr = AttributedString(codeText)
                codeAttr.font = .system(.body, design: .monospaced)
                codeAttr.foregroundColor = .pink
                codeAttr.backgroundColor = Color(.systemGray6)
                result.append(codeAttr)

                remaining = String(remaining[codeEnd.upperBound...])
            } else if let boldStart = remaining.range(of: "⟨BOLD⟩"),
                      let boldEnd = remaining.range(of: "⟨/BOLD⟩") {
                let beforeText = String(remaining[remaining.startIndex..<boldStart.lowerBound])
                result.append(buildPlainAttributedString(from: beforeText))

                let boldText = String(remaining[boldStart.upperBound..<boldEnd.lowerBound])
                var boldAttr = AttributedString(boldText)
                boldAttr.font = .body.bold()
                result.append(boldAttr)

                remaining = String(remaining[boldEnd.upperBound...])
            } else if let italicStart = remaining.range(of: "⟨ITALIC⟩"),
                      let italicEnd = remaining.range(of: "⟨/ITALIC⟩") {
                let beforeText = String(remaining[remaining.startIndex..<italicStart.lowerBound])
                result.append(buildPlainAttributedString(from: beforeText))

                let italicText = String(remaining[italicStart.upperBound..<italicEnd.lowerBound])
                var italicAttr = AttributedString(italicText)
                italicAttr.font = .body.italic()
                result.append(italicAttr)

                remaining = String(remaining[italicEnd.upperBound...])
            } else {
                // No more markers, add remaining text
                result.append(AttributedString(remaining))
                break
            }
        }

        return result
    }

    private func buildPlainAttributedString(from text: String) -> AttributedString {
        // Recursively process in case there are nested markers
        if text.contains("⟨") {
            return buildAttributedString(from: text)
        }
        return AttributedString(text)
    }
}

enum MarkdownBlock {
    case text(String)
    case code(String, language: String?)
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var isCopied = false

    private var displayLanguage: String {
        language?.isEmpty == false ? language! : "code"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: language + copy button
            HStack {
                Text(displayLanguage)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                    isCopied = true
                    HapticManager.shared.notification(.success)

                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        isCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(isCopied ? .green : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.15, green: 0.15, blue: 0.15))

            // Code content with horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(white: 0.9))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack {
        AIChatView(store: AIChatStore(), initialConversation: nil)
    }
}
