//
//  TranslationService.swift
//  xiaojinpro
//
//  Translation service using AI Router
//  Uses gemini-3-pro-preview for translation
//

import Foundation

// MARK: - Translation Service
@MainActor
class TranslationService: ObservableObject {
    static let shared = TranslationService()

    private let secretStore = SecretStoreService.shared
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Model used for translation (Gemini for speed)
    private let translationModel = "gemini-3-pro-preview"

    @Published var isTranslating = false
    @Published var error: String?

    private init() {
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Public Methods

    /// Translate text from source to target language
    /// - Parameters:
    ///   - text: Text to translate
    ///   - from: Source language (e.g., "en-US")
    ///   - to: Target language (e.g., "zh-CN")
    /// - Returns: Translated text
    func translate(
        text: String,
        from sourceLanguage: String = "en-US",
        to targetLanguage: String = "zh-CN"
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        isTranslating = true
        error = nil
        defer { isTranslating = false }

        do {
            let credentials = try await secretStore.getBackendCredentials()

            // Build translation prompt
            let targetLangName = languageName(for: targetLanguage)
            let prompt = buildTranslationPrompt(text: text, targetLanguage: targetLangName)

            // Build request
            let request = ChatCompletionRequest(
                model: translationModel,
                messages: [ChatMessage(role: .user, text: prompt)],
                stream: false,
                temperature: 0.3,
                maxTokens: 1024
            )

            // Create URL request
            let url = URL(string: "\(credentials.baseURL)/v1/chat/completions")!
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.httpBody = try encoder.encode(request)
            urlRequest.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw InterpreterError.translationFailed("Invalid response")
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw InterpreterError.translationFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }

            // Parse response
            let chatResponse = try decoder.decode(TranslationResponse.self, from: data)

            guard let translatedText = chatResponse.choices.first?.message?.content else {
                throw InterpreterError.translationFailed("Empty response")
            }

            return cleanTranslationOutput(translatedText)

        } catch let interpreterError as InterpreterError {
            self.error = interpreterError.localizedDescription
            throw interpreterError
        } catch {
            let interpreterError = InterpreterError.translationFailed(error.localizedDescription)
            self.error = interpreterError.localizedDescription
            throw interpreterError
        }
    }

    /// Translate with retry logic
    func translateWithRetry(
        text: String,
        from sourceLanguage: String = "en-US",
        to targetLanguage: String = "zh-CN",
        maxRetries: Int = 2
    ) async throws -> String {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                return try await translate(text: text, from: sourceLanguage, to: targetLanguage)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    // Wait before retry (exponential backoff)
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 500_000_000))
                }
            }
        }

        throw lastError ?? InterpreterError.translationFailed("Unknown error")
    }

    // MARK: - Private Methods

    private func buildTranslationPrompt(text: String, targetLanguage: String) -> String {
        """
        Translate the following text to \(targetLanguage). \
        Only output the translation, nothing else. \
        Preserve the original meaning and tone.

        \(text)
        """
    }

    private func languageName(for code: String) -> String {
        switch code.lowercased() {
        case "zh-cn", "zh-hans", "zh":
            return "Simplified Chinese"
        case "zh-tw", "zh-hant":
            return "Traditional Chinese"
        case "en-us", "en":
            return "English"
        case "ja":
            return "Japanese"
        case "ko":
            return "Korean"
        case "es":
            return "Spanish"
        case "fr":
            return "French"
        case "de":
            return "German"
        default:
            return code
        }
    }

    private func cleanTranslationOutput(_ text: String) -> String {
        // Remove any quotes or formatting that the model might have added
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove surrounding quotes if present
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        return cleaned
    }
}

// MARK: - Translation Response Models

private struct TranslationResponse: Codable {
    let id: String?
    let object: String?
    let choices: [TranslationChoice]
}

private struct TranslationChoice: Codable {
    let index: Int?
    let message: TranslationMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

private struct TranslationMessage: Codable {
    let role: String?
    let content: String?
}

// MARK: - Mock Translation Service (for testing)

#if DEBUG
class MockTranslationService: TranslationService {
    override func translate(
        text: String,
        from sourceLanguage: String = "en-US",
        to targetLanguage: String = "zh-CN"
    ) async throws -> String {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Return mock translation
        let translations: [String: String] = [
            "Hello, how are you doing today?": "你好，你今天怎么样？",
            "The weather is nice.": "天气很好。",
            "I'm doing great, thank you!": "我很好，谢谢！"
        ]

        return translations[text] ?? "[\(text) 的翻译]"
    }
}
#endif
