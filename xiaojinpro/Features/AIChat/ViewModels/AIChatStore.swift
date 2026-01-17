//
//  AIChatStore.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation
import SwiftUI
import PhotosUI
import UIKit

// MARK: - Pending Attachment
struct PendingAttachment: Identifiable {
    let id = UUID()
    let data: Data
    let fileName: String
    let mimeType: String
    let fileType: String // image, video, document
    var thumbnail: UIImage?

    var fileSize: Int { data.count }

    var icon: String {
        switch fileType {
        case "image": return "photo"
        case "video": return "video"
        case "document": return "doc"
        default: return "paperclip"
        }
    }
}

// MARK: - AI Chat Store
@MainActor
class AIChatStore: ObservableObject {
    // Services
    private let routerService = AIRouterService.shared
    private let conversationService = AIConversationService.shared

    // Conversations List
    @Published var conversations: [AIConversation] = []
    @Published var isLoadingConversations = false
    @Published var hasMoreConversations = false
    @Published var conversationsCursor: String?

    // Current Conversation
    @Published var currentConversation: AIConversation?
    @Published var messages: [AIMessage] = []
    @Published var isLoadingMessages = false

    // Chat State
    @Published var isSending = false
    @Published var isStreaming = false
    @Published var streamingContent = ""
    @Published var error: String?

    // Model Selection
    @Published var selectedModel: AIModel = AIModel.defaultModel
    @Published var availableModels: [AIModel] = AIModel.defaultModels

    // Input State
    @Published var inputText = ""
    @Published var pendingAttachments: [PendingAttachment] = []

    // Settings
    @Published var systemPrompt: String = ""
    @Published var temperature: Double = 0.7

    private var streamTask: Task<Void, Never>?

    // MARK: - Conversations Management

    func loadConversations(refresh: Bool = false) async {
        if refresh {
            conversationsCursor = nil
        }

        guard !isLoadingConversations else { return }
        isLoadingConversations = true
        error = nil

        do {
            let response = try await conversationService.listConversations(
                includeArchived: false,
                limit: 20,
                cursor: refresh ? nil : conversationsCursor
            )

            if refresh {
                conversations = response.data
            } else {
                conversations.append(contentsOf: response.data)
            }

            hasMoreConversations = response.hasMore
            conversationsCursor = response.nextCursor
        } catch let apiError as APIError {
            error = apiError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }

        isLoadingConversations = false
    }

    func createNewConversation() async -> AIConversation? {
        do {
            let conversation = try await conversationService.createConversation(
                model: selectedModel.id,
                systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
                temperature: temperature
            )

            // Insert at the beginning
            conversations.insert(conversation, at: 0)
            return conversation
        } catch let apiError as APIError {
            error = apiError.localizedDescription
            return nil
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func selectConversation(_ conversation: AIConversation) async {
        currentConversation = conversation
        messages = []
        streamingContent = ""

        // Update selected model to match conversation
        if let model = availableModels.first(where: { $0.id == conversation.model }) {
            selectedModel = model
        }

        await loadMessages()
    }

    func deleteConversation(_ conversation: AIConversation) async {
        do {
            try await conversationService.deleteConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }

            if currentConversation?.id == conversation.id {
                currentConversation = nil
                messages = []
            }
        } catch let apiError as APIError {
            error = apiError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    func archiveConversation(_ conversation: AIConversation) async {
        do {
            _ = try await conversationService.updateConversation(
                id: conversation.id,
                isArchived: true
            )
            conversations.removeAll { $0.id == conversation.id }
        } catch let apiError as APIError {
            error = apiError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateConversationTitle(_ conversation: AIConversation, title: String) async {
        do {
            let updated = try await conversationService.updateConversation(
                id: conversation.id,
                title: title
            )

            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index] = updated
            }

            if currentConversation?.id == conversation.id {
                currentConversation = updated
            }
        } catch let apiError as APIError {
            error = apiError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Messages Management

    func loadMessages() async {
        guard let conversation = currentConversation else { return }

        isLoadingMessages = true
        error = nil

        do {
            let response = try await conversationService.listMessages(
                conversationId: conversation.id,
                limit: 100
            )
            messages = response.data
        } catch let apiError as APIError {
            error = apiError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }

        isLoadingMessages = false
    }

    // MARK: - Send Message

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        guard !isSending else { return }

        // Haptic feedback on send
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        isSending = true
        error = nil

        // Create conversation if needed
        var conversation = currentConversation
        if conversation == nil {
            conversation = await createNewConversation()
            guard let conv = conversation else {
                isSending = false
                return
            }
            currentConversation = conv
        }

        guard let conversationId = conversation?.id else {
            isSending = false
            return
        }

        // Build content parts for multimodal
        var contentParts: [AIContentPart]? = nil
        var attachmentIds: [String] = []

        // Upload attachments if any
        if !pendingAttachments.isEmpty {
            contentParts = []

            // Add text first if present
            if !text.isEmpty {
                contentParts?.append(.text(text))
            }

            for attachment in pendingAttachments {
                do {
                    // Create attachment record and get upload URL
                    let response = try await conversationService.createAttachment(
                        conversationId: conversationId,
                        fileName: attachment.fileName,
                        fileType: attachment.fileType,
                        fileSize: attachment.fileSize,
                        mimeType: attachment.mimeType
                    )

                    // Upload the file
                    try await conversationService.uploadAttachment(
                        to: response.uploadUrl,
                        data: attachment.data,
                        mimeType: attachment.mimeType
                    )

                    attachmentIds.append(response.attachmentId)

                    // Add to content parts
                    // Note: The actual URL will be resolved by the backend
                    let placeholderUrl = "attachment://\(response.attachmentId)"
                    switch attachment.fileType {
                    case "image":
                        contentParts?.append(.imageUrl(placeholderUrl))
                    case "video":
                        contentParts?.append(.videoUrl(placeholderUrl))
                    default:
                        contentParts?.append(.fileUrl(placeholderUrl, mimeType: attachment.mimeType))
                    }
                } catch {
                    print("Failed to upload attachment: \(error)")
                }
            }
        }

        // Create user message
        do {
            let userMessage = try await conversationService.createMessage(
                conversationId: conversationId,
                role: .user,
                content: text,
                contentParts: contentParts,
                attachmentIds: attachmentIds.isEmpty ? nil : attachmentIds
            )

            messages.append(userMessage)
        } catch {
            self.error = "Failed to save message: \(error.localizedDescription)"
            isSending = false
            return
        }

        // Clear input
        inputText = ""
        pendingAttachments = []

        // Generate AI response
        await generateResponse(conversationId: conversationId)

        isSending = false
    }

    private func generateResponse(conversationId: String) async {
        isStreaming = true
        streamingContent = ""

        // Create a temporary assistant message for streaming display
        let tempId = UUID().uuidString
        let tempMessage = AIMessage(
            id: tempId,
            conversationId: conversationId,
            role: .assistant,
            content: "",
            contentParts: nil,
            promptTokens: nil,
            completionTokens: nil,
            modelUsed: selectedModel.id,
            finishReason: nil,
            createdAt: Date()
        )
        messages.append(tempMessage)

        // Stream the response
        var fullContent = ""

        streamTask = Task {
            do {
                for try await chunk in routerService.streamChatCompletion(
                    model: selectedModel.id,
                    messages: messages.filter { $0.id != tempId }, // Exclude temp message
                    systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
                    temperature: temperature
                ) {
                    fullContent += chunk
                    streamingContent = fullContent

                    // Update the temp message content for display
                    if let index = messages.firstIndex(where: { $0.id == tempId }) {
                        messages[index].content = fullContent
                    }
                }
            } catch {
                self.error = "Generation failed: \(error.localizedDescription)"
            }
        }

        await streamTask?.value

        isStreaming = false

        // Save the assistant message to cloud
        if !fullContent.isEmpty {
            do {
                let savedMessage = try await conversationService.createMessage(
                    conversationId: conversationId,
                    role: .assistant,
                    content: fullContent
                )

                // Replace temp message with saved one
                if let index = messages.firstIndex(where: { $0.id == tempId }) {
                    messages[index] = savedMessage
                }

                // Update conversation title if this is the first exchange
                if let conv = currentConversation, conv.title == nil, messages.count <= 2 {
                    await generateConversationTitle(conversationId: conversationId, firstMessage: inputText.isEmpty ? fullContent : inputText)
                }
            } catch {
                print("Failed to save assistant message: \(error)")
            }
        } else {
            // Remove temp message if generation failed
            messages.removeAll { $0.id == tempId }
        }
    }

    private func generateConversationTitle(conversationId: String, firstMessage: String) async {
        // Generate a short title from the first message
        let title = String(firstMessage.prefix(50))
        await updateConversationTitle(
            currentConversation!,
            title: title.count < firstMessage.count ? title + "..." : title
        )
    }

    func cancelGeneration() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func regenerateLastResponse() async {
        // Remove last assistant message
        if let lastMessage = messages.last, lastMessage.role == .assistant {
            messages.removeLast()

            if let conversation = currentConversation {
                // Delete from cloud
                try? await conversationService.deleteMessage(
                    conversationId: conversation.id,
                    messageId: lastMessage.id
                )

                // Regenerate
                await generateResponse(conversationId: conversation.id)
            }
        }
    }

    func deleteMessage(_ message: AIMessage) async {
        guard let conversation = currentConversation else { return }

        do {
            try await conversationService.deleteMessage(
                conversationId: conversation.id,
                messageId: message.id
            )
            messages.removeAll { $0.id == message.id }

            // Haptic feedback
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            self.error = "Failed to delete message: \(error.localizedDescription)"
        }
    }

    // MARK: - Attachments

    func addImageAttachment(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }

        let attachment = PendingAttachment(
            data: data,
            fileName: "image_\(Date().timeIntervalSince1970).jpg",
            mimeType: "image/jpeg",
            fileType: "image",
            thumbnail: image
        )

        pendingAttachments.append(attachment)
    }

    func addDocumentAttachment(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let mimeType = mimeTypeForPath(url.pathExtension)

            let attachment = PendingAttachment(
                data: data,
                fileName: url.lastPathComponent,
                mimeType: mimeType,
                fileType: "document"
            )

            pendingAttachments.append(attachment)
        } catch {
            self.error = "Failed to load file: \(error.localizedDescription)"
        }
    }

    func removeAttachment(_ attachment: PendingAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    private func mimeTypeForPath(_ pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "txt": return "text/plain"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Models

    func loadModels() async {
        do {
            try await routerService.fetchModels()
            availableModels = routerService.availableModels
        } catch {
            // Use default models on error
            availableModels = AIModel.defaultModels
        }
    }

    func selectModel(_ model: AIModel) {
        selectedModel = model

        // Update current conversation model if exists
        if let conversation = currentConversation {
            Task {
                _ = try? await conversationService.updateConversation(
                    id: conversation.id,
                    model: model.id
                )
            }
        }
    }

    // MARK: - Clear

    func clearCurrentConversation() {
        currentConversation = nil
        messages = []
        streamingContent = ""
        inputText = ""
        pendingAttachments = []
    }
}
