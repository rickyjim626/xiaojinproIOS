//
//  SecretStoreService.swift
//  xiaojinpro
//
//  Secret Store 客户端
//  两阶段认证：
//  1. 用 JWT 从 AuthCenter 获取 Secret Store 的 API Key
//  2. 用 API Key 直接访问 Secret Store
//

import Foundation

// MARK: - Secret Store Configuration

enum SecretStoreConfig {
    /// AuthCenter 端点
    static let authBaseURL = "https://auth.xiaojinpro.com"

    /// 凭证缓存时间 (24小时)
    static let credentialsCacheDuration: TimeInterval = 86400

    /// Backend namespace 中的密钥名称
    static let backendAPIKeyName = "BACKEND_API_KEY"
    static let backendBaseURLName = "BACKEND_ENDPOINT"
}

// MARK: - Secret Store Token Response

/// 从 AuthCenter 获取的 Secret Store 凭证
private struct SecretStoreTokenResponse: Codable {
    let url: String
    let apiKey: String
    let namespace: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case url
        case apiKey = "api_key"
        case namespace
        case expiresIn = "expires_in"
    }
}

// MARK: - Secret Store Secret Response

/// Secret Store 返回的密钥值
/// 实际响应包含更多字段，但我们只需要 value
private struct SecretStoreSecretResponse: Codable {
    let value: String
    // 其他字段是可选的，我们不关心
    let namespace: String?
    let key: String?
    let format: String?
    let version: Int?
}

// MARK: - Backend Credentials

struct BackendCredentials {
    let apiKey: String
    let baseURL: String
    let fetchedAt: Date

    var isExpired: Bool {
        Date().timeIntervalSince(fetchedAt) > SecretStoreConfig.credentialsCacheDuration
    }
}

// MARK: - Secret Store Service

/// Secret Store 服务
/// 使用两阶段认证访问 Secret Store：
/// 1. 先用 JWT 调用 /admin/secrets/token 获取 Secret Store 凭证
/// 2. 然后用 X-API-Key 直接访问 Secret Store
@MainActor
class SecretStoreService: ObservableObject {
    static let shared = SecretStoreService()

    @Published private(set) var isLoading = false
    @Published var error: String?

    // Secret Store 凭证（从 AuthCenter 获取）
    private var secretStoreURL: String?
    private var secretStoreAPIKey: String?
    private var secretStoreNamespace: String?
    private var credentialsFetchedAt: Date?

    // Backend 凭证缓存
    private var cachedBackendCredentials: BackendCredentials?

    // 防止并发获取凭证
    private var fetchCredentialsTask: Task<Void, Error>?

    private init() {}

    // MARK: - Credential Management

    /// 确保已获取 Secret Store 凭证
    private func ensureCredentials() async throws {
        // 如果凭证有效，直接返回
        if let fetchedAt = credentialsFetchedAt,
           Date().timeIntervalSince(fetchedAt) < SecretStoreConfig.credentialsCacheDuration,
           secretStoreAPIKey != nil {
            return
        }

        // 如果正在获取凭证，等待完成
        if let existingTask = fetchCredentialsTask {
            try await existingTask.value
            return
        }

        // 创建获取凭证的任务
        let task = Task<Void, Error> {
            try await self.fetchCredentials()
        }
        fetchCredentialsTask = task

        do {
            try await task.value
            fetchCredentialsTask = nil
        } catch {
            fetchCredentialsTask = nil
            throw error
        }
    }

    /// 从 AuthCenter 获取 Secret Store 凭证
    private func fetchCredentials() async throws {
        let endpoint = "\(SecretStoreConfig.authBaseURL)/admin/secrets/token"

        guard let url = URL(string: endpoint) else {
            throw SecretStoreError.invalidURL
        }

        // 获取 JWT token
        guard let accessToken = await AuthManager.shared.accessToken else {
            throw SecretStoreError.notAuthenticated
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SecretStoreError.invalidResponse
        }

        // 401/403 时强制登出
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            await forceLogout()
            throw SecretStoreError.unauthorized
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SecretStoreError.httpError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        let decoder = JSONDecoder()
        let tokenResponse = try decoder.decode(SecretStoreTokenResponse.self, from: data)

        self.secretStoreURL = tokenResponse.url
        self.secretStoreAPIKey = tokenResponse.apiKey
        self.secretStoreNamespace = tokenResponse.namespace
        self.credentialsFetchedAt = Date()

        print("✅ 已获取 Secret Store 凭证，namespace: \(tokenResponse.namespace)")
    }

    /// 清除凭证（登出时调用）
    func clearCache() {
        secretStoreURL = nil
        secretStoreAPIKey = nil
        secretStoreNamespace = nil
        credentialsFetchedAt = nil
        cachedBackendCredentials = nil
    }

    /// 强制登出（认证失败时调用）
    private func forceLogout() async {
        print("⚠️ Secret Store 认证失败，强制登出")
        await AuthManager.shared.signOut()
    }

    // MARK: - Public Methods

    /// 获取 backend 凭证 (API key 和 base URL)
    func getBackendCredentials() async throws -> BackendCredentials {
        // 返回缓存（如果有效）
        if let cached = cachedBackendCredentials, !cached.isExpired {
            return cached
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // 确保有 Secret Store 凭证
            try await ensureCredentials()

            // 并发获取两个密钥
            async let apiKeyTask = getSecret(SecretStoreConfig.backendAPIKeyName)
            async let baseURLTask = getSecret(SecretStoreConfig.backendBaseURLName)

            let (apiKey, baseURL) = try await (apiKeyTask, baseURLTask)

            guard let apiKey = apiKey, let baseURL = baseURL else {
                throw SecretStoreError.missingValue
            }

            let credentials = BackendCredentials(
                apiKey: apiKey,
                baseURL: baseURL,
                fetchedAt: Date()
            )

            cachedBackendCredentials = credentials
            print("✅ Backend credentials fetched: baseURL=\(baseURL)")

            return credentials
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    /// 获取单个密钥
    func getSecret(_ key: String) async throws -> String? {
        try await ensureCredentials()

        guard let baseURL = secretStoreURL,
              let apiKey = secretStoreAPIKey,
              let namespace = secretStoreNamespace else {
            throw SecretStoreError.notAuthenticated
        }

        return try await getSecret(key, namespace: namespace, baseURL: baseURL, apiKey: apiKey)
    }

    /// 获取指定 namespace 的密钥
    private func getSecret(_ key: String, namespace: String, baseURL: String, apiKey: String) async throws -> String? {
        // 直接访问 Secret Store: GET /api/v2/secrets/{namespace}/{key}
        let encodedNamespace = namespace.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? namespace
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let endpoint = "\(baseURL)/api/v2/secrets/\(encodedNamespace)/\(encodedKey)"

        guard let url = URL(string: endpoint) else {
            throw SecretStoreError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SecretStoreError.invalidResponse
        }

        // 404 表示密钥不存在
        if httpResponse.statusCode == 404 {
            return nil
        }

        // 401/403 可能是凭证过期
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            clearCache()
            throw SecretStoreError.unauthorized
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SecretStoreError.httpError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        let decoder = JSONDecoder()
        let secretResponse = try decoder.decode(SecretStoreSecretResponse.self, from: data)

        return secretResponse.value
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
            return "Invalid Secret Store URL"
        case .invalidResponse:
            return "Invalid response from Secret Store"
        case .httpError(let code, let message):
            return "Secret Store error \(code): \(message ?? "Unknown")"
        case .missingValue:
            return "Secret value not found"
        case .notAuthenticated:
            return "请先登录"
        case .unauthorized:
            return "会话已过期，请重新登录"
        }
    }
}
