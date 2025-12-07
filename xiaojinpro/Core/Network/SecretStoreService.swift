//
//  SecretStoreService.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/6.
//

import Foundation

// MARK: - Secret Store Configuration
/// Configuration for accessing backend credentials via auth service's secret proxy
enum SecretStoreConfig {
    // Auth service endpoint that proxies secret-store requests
    // Uses JWT authentication (no hardcoded secret-store credentials needed)
    static let authBaseURL = "https://auth.xiaojinpro.com"

    // Namespace containing backend credentials
    static let backendNamespace = "frontend-backend"

    // Keys in the backend namespace
    static let backendAPIKeyName = "BACKEND_API_KEY"
    static let backendBaseURLName = "BACKEND_ENDPOINT"  // Note: key is ENDPOINT not BASE_URL

    // Cache duration (1 hour)
    static let cacheDuration: TimeInterval = 3600
}

// MARK: - Secret Response from Auth Service
struct SecretResponse: Codable {
    let key: String
    let value: String
    let namespace: String
}

// MARK: - Backend Credentials
struct BackendCredentials {
    let apiKey: String
    let baseURL: String
    let fetchedAt: Date

    var isExpired: Bool {
        Date().timeIntervalSince(fetchedAt) > SecretStoreConfig.cacheDuration
    }
}

// MARK: - Secret Store Service
/// Service for fetching backend credentials via auth service's secret proxy
/// Uses JWT authentication - no hardcoded secret-store credentials
@MainActor
class SecretStoreService: ObservableObject {
    static let shared = SecretStoreService()

    @Published private(set) var isLoading = false
    @Published var error: String?

    private var cachedCredentials: BackendCredentials?
    private let decoder: JSONDecoder

    private init() {
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Public Methods

    /// Get backend credentials (API key and base URL)
    /// Returns cached credentials if still valid, otherwise fetches fresh
    /// Requires user to be logged in (uses JWT from AuthManager)
    func getBackendCredentials() async throws -> BackendCredentials {
        // Return cached if still valid
        if let cached = cachedCredentials, !cached.isExpired {
            return cached
        }

        // Fetch fresh credentials
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Get JWT token from AuthManager
        guard let token = await AuthManager.shared.accessToken else {
            throw SecretStoreError.notAuthenticated
        }

        do {
            async let apiKeyTask = fetchSecret(
                namespace: SecretStoreConfig.backendNamespace,
                key: SecretStoreConfig.backendAPIKeyName,
                token: token
            )
            async let baseURLTask = fetchSecret(
                namespace: SecretStoreConfig.backendNamespace,
                key: SecretStoreConfig.backendBaseURLName,
                token: token
            )

            let (apiKey, baseURL) = try await (apiKeyTask, baseURLTask)

            let credentials = BackendCredentials(
                apiKey: apiKey,
                baseURL: baseURL,
                fetchedAt: Date()
            )

            cachedCredentials = credentials
            print("✅ Backend credentials fetched via auth proxy: baseURL=\(baseURL)")

            return credentials
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    /// Clear cached credentials (useful for logout or forced refresh)
    func clearCache() {
        cachedCredentials = nil
    }

    // MARK: - Private Methods

    /// Fetch a secret via auth service's admin/secrets proxy endpoint
    /// Uses JWT authentication from the logged-in user
    private func fetchSecret(namespace: String, key: String, token: String) async throws -> String {
        // Format: /admin/secrets/namespace%2Fkey (slash must be URL-encoded as single path segment)
        // Backend route is /admin/secrets/:key and parses namespace/key from the key parameter
        let combinedKey = "\(namespace)/\(key)"

        // URL-encode including the slash character (urlPathAllowed doesn't encode /)
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "/")
        let encodedKey = combinedKey.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? combinedKey

        let urlString = "\(SecretStoreConfig.authBaseURL)/admin/secrets/\(encodedKey)"

        guard let url = URL(string: urlString) else {
            throw SecretStoreError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SecretStoreError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8)
            if httpResponse.statusCode == 401 {
                throw SecretStoreError.unauthorized
            }
            throw SecretStoreError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        // Parse response
        let secretResponse = try decoder.decode(SecretResponse.self, from: data)
        return extractValue(from: secretResponse.value)
    }

    /// Extract the actual value from potentially nested JSON
    private func extractValue(from value: String) -> String {
        var current = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to parse as JSON and extract nested value (in case of double-encoded values)
        for _ in 0..<3 {
            guard let data = current.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let innerValue = json["value"] as? String else {
                break
            }
            current = innerValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return current
    }
}

// MARK: - Secret Store Error
enum SecretStoreError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case missingValue
    case notAuthenticated
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid secret store URL"
        case .invalidResponse:
            return "Invalid response from secret store"
        case .httpError(let code, let message):
            return "Secret store error \(code): \(message ?? "Unknown")"
        case .missingValue:
            return "Secret value not found"
        case .notAuthenticated:
            return "Please sign in to access backend services"
        case .unauthorized:
            return "Session expired - please sign in again"
        }
    }
}
