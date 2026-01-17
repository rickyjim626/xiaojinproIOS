//
//  AuthManager.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation
import AuthenticationServices
import Combine

// MARK: - User Model
/// Note: Custom decoder handles id as either String or Int from backend
/// Properties map: avatar_url → avatarUrl, subscription_tier → subscriptionTier, etc.
struct User: Decodable, Identifiable, Equatable {
    let id: String
    let email: String?
    let name: String?
    let avatarUrl: String?
    let subscriptionTier: String?
    let createdAt: Date?
    let isAdmin: Bool?  // maps from is_admin

    enum CodingKeys: String, CodingKey {
        case id, email, name
        case avatarUrl = "avatar_url"
        case subscriptionTier = "subscription_tier"
        case createdAt = "created_at"
        case isAdmin = "is_admin"
        // Alternative keys from different endpoints
        case displayName = "display_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle id as either String or Int
        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            throw DecodingError.typeMismatch(String.self, DecodingError.Context(
                codingPath: [CodingKeys.id],
                debugDescription: "Expected String or Int for id"
            ))
        }

        email = try container.decodeIfPresent(String.self, forKey: .email)
        // Try both 'name' and 'display_name' keys
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        subscriptionTier = try container.decodeIfPresent(String.self, forKey: .subscriptionTier)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin)
    }

    init(id: String, email: String?, name: String?, avatarUrl: String?, subscriptionTier: String?, createdAt: Date?, isAdmin: Bool?) {
        self.id = id
        self.email = email
        self.name = name
        self.avatarUrl = avatarUrl
        self.subscriptionTier = subscriptionTier
        self.createdAt = createdAt
        self.isAdmin = isAdmin
    }

    var displayName: String {
        name ?? email ?? "User"
    }

    var isAdminUser: Bool {
        isAdmin == true || subscriptionTier == "studio" || subscriptionTier == "admin"
    }

    /// 是否为订阅用户 (creator_beta 或 studio)
    var isCreator: Bool {
        subscriptionTier == "creator_beta" || subscriptionTier == "studio"
    }

    /// 是否为免费用户
    var isFree: Bool {
        subscriptionTier == nil || subscriptionTier == "free"
    }

    /// 计划显示名称
    var planDisplayName: String {
        switch subscriptionTier {
        case "creator_beta": return "Creator Beta"
        case "studio": return "Studio"
        case "admin": return "Admin"
        default: return "Free"
        }
    }

    static func == (lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Auth State
enum AuthState: Equatable {
    case unknown
    case authenticated(User)
    case unauthenticated

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    var user: User? {
        if case .authenticated(let user) = self { return user }
        return nil
    }
}

// MARK: - Auth Credentials
/// Note: No CodingKeys needed - uses automatic snake_case conversion
struct AuthCredentials: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
}

// MARK: - Login Request/Response

/// Request for POST /auth/email/token
/// Note: No CodingKeys needed because APIClient uses .convertToSnakeCase for encoding
struct LoginTokenRequest: Codable {
    let email: String
    let password: String
    let clientId: String
    let scope: String

    init(email: String, password: String) {
        self.email = email
        self.password = password
        self.clientId = "xiaojinpro-ios"
        self.scope = "openid profile email offline_access"
    }
}

/// Response from POST /auth/email/token
/// Note: No CodingKeys needed because APIClient uses .convertFromSnakeCase
struct TokenResponse: Codable {
    let tokenType: String
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int64
    let user: TokenUserInfo
}

/// User info from token response
/// Note: No CodingKeys needed because APIClient uses .convertFromSnakeCase
struct TokenUserInfo: Codable {
    let id: String
    let email: String?
    let name: String?
    let picture: String?
    let isAdmin: Bool
    let plan: String?  // subscription_tier (nullable)

    /// Convert to User model
    func toUser() -> User {
        User(
            id: id,
            email: email,
            name: name,
            avatarUrl: picture,
            subscriptionTier: plan,
            createdAt: nil,
            isAdmin: isAdmin
        )
    }
}

/// Legacy login request (session-based)
struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct RegisterRequest: Codable {
    let email: String
    let password: String
    let name: String?
}

/// Note: No CodingKeys needed - uses automatic snake_case conversion
struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let user: User?
}

// MARK: - OAuth Token Request
/// Note: No CodingKeys needed - uses automatic snake_case conversion
struct OAuthTokenRequest: Codable {
    let grantType: String
    let code: String
    let redirectUri: String
    let provider: String
}

// MARK: - Apple Sign In Request
/// Note: No CodingKeys needed - uses automatic snake_case conversion
struct AppleSignInRequest: Codable {
    let identityToken: String
    let authorizationCode: String?
    let email: String?
    let fullName: String?
}

// MARK: - OAuth Presentation Context Provider
class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Auth Manager
@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var state: AuthState = .unknown
    @Published private(set) var isLoading = false
    @Published var error: String?

    private let keychainKey = "com.xiaojinpro.auth.credentials"
    private var refreshTask: Task<Void, Never>?

    var accessToken: String? {
        get async {
            guard let credentials = loadCredentials() else { return nil }

            // Auto refresh if expired
            if credentials.isExpired {
                await refreshTokenIfNeeded()
                return loadCredentials()?.accessToken
            }

            return credentials.accessToken
        }
    }

    var currentUser: User? {
        state.user
    }

    private init() {
        // Check for existing session on init
        Task {
            await checkExistingSession()
        }
    }

    // MARK: - Public Methods

    func signIn(email: String, password: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Use new /auth/email/token endpoint for JWT token exchange
            let request = LoginTokenRequest(email: email, password: password)
            let response: TokenResponse = try await APIClient.shared.post(.loginToken, body: request)

            let credentials = AuthCredentials(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
            )

            saveCredentials(credentials)

            // User info is included in token response
            let user = response.user.toUser()
            state = .authenticated(user)

            print("✅ 登录成功: \(user.email ?? "unknown"), plan: \(user.planDisplayName), isAdmin: \(user.isAdmin)")

        } catch let apiError as APIError {
            error = apiError.localizedDescription
            throw apiError
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func signUp(email: String, password: String, name: String?) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let request = RegisterRequest(email: email, password: password, name: name)
            let response: AuthResponse = try await APIClient.shared.post(.register, body: request)

            let credentials = AuthCredentials(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
            )

            saveCredentials(credentials)

            let user: User
            if let responseUser = response.user {
                user = responseUser
            } else {
                user = try await fetchCurrentUser()
            }
            state = .authenticated(user)

        } catch let apiError as APIError {
            error = apiError.localizedDescription
            throw apiError
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    func signOut() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await APIClient.shared.delete(.logout)
        } catch {
            // Ignore logout errors, still clear local state
            print("Logout error: \(error)")
        }

        clearCredentials()
        SecretStoreService.shared.clearCache()
        state = .unauthenticated
    }

    func refreshUser() async {
        guard state.isAuthenticated else { return }

        do {
            let user = try await fetchCurrentUser()
            state = .authenticated(user)
        } catch {
            print("Failed to refresh user: \(error)")
        }
    }

    // MARK: - OAuth (for WeChat, etc.)

    func signInWithOAuth(provider: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let authURL = URL(string: "\(APIConfig.authBaseURL)/oauth2/authorize?provider=\(provider)&redirect_uri=xiaojinpro://oauth/callback")!

        // Use ASWebAuthenticationSession for OAuth flow
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "xiaojinpro"
            ) { callbackURL, error in
                if let error = error {
                    self.error = "OAuth 登录失败: \(error.localizedDescription)"
                    continuation.resume()
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.error = "OAuth 登录失败: 无法获取授权码"
                    continuation.resume()
                    return
                }

                Task {
                    do {
                        try await self.exchangeOAuthCode(code, provider: provider)
                    } catch {
                        self.error = "OAuth 登录失败: \(error.localizedDescription)"
                    }
                    continuation.resume()
                }
            }

            session.presentationContextProvider = OAuthPresentationContextProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func exchangeOAuthCode(_ code: String, provider: String) async throws {
        let body = OAuthTokenRequest(
            grantType: "authorization_code",
            code: code,
            redirectUri: "xiaojinpro://oauth/callback",
            provider: provider
        )

        let response: AuthResponse = try await APIClient.shared.post(.refreshToken, body: body)

        let credentials = AuthCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )

        saveCredentials(credentials)

        let user: User
        if let responseUser = response.user {
            user = responseUser
        } else {
            user = try await fetchCurrentUser()
        }
        state = .authenticated(user)
    }

    // MARK: - Apple Sign In

    func signInWithApple(
        identityToken: String,
        authorizationCode: String?,
        email: String?,
        fullName: String?
    ) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let body = AppleSignInRequest(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            email: email,
            fullName: fullName
        )

        let response: AuthResponse = try await APIClient.shared.post(.appleSignIn, body: body)

        let credentials = AuthCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )

        saveCredentials(credentials)

        let user: User
        if let responseUser = response.user {
            user = responseUser
        } else {
            user = try await fetchCurrentUser()
        }
        state = .authenticated(user)
    }

    // MARK: - Private Methods

    private func checkExistingSession() async {
        guard let credentials = loadCredentials() else {
            state = .unauthenticated
            return
        }

        if credentials.isExpired {
            await refreshTokenIfNeeded()
        }

        do {
            let user = try await fetchCurrentUser()
            state = .authenticated(user)
        } catch {
            clearCredentials()
            state = .unauthenticated
        }
    }

    private func fetchCurrentUser() async throws -> User {
        try await APIClient.shared.get(.userMe)
    }

    private func refreshTokenIfNeeded() async {
        guard let credentials = loadCredentials(),
              let refreshToken = credentials.refreshToken else {
            return
        }

        // Avoid concurrent refresh attempts
        if refreshTask != nil { return }

        refreshTask = Task {
            defer { refreshTask = nil }

            do {
                let body = ["grant_type": "refresh_token", "refresh_token": refreshToken]
                let response: AuthResponse = try await APIClient.shared.post(.refreshToken, body: body)

                let newCredentials = AuthCredentials(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken ?? refreshToken,
                    expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
                )

                saveCredentials(newCredentials)
            } catch {
                print("Token refresh failed: \(error)")
                clearCredentials()
                await MainActor.run {
                    state = .unauthenticated
                }
            }
        }

        await refreshTask?.value
    }

    // MARK: - Keychain Storage

    private let keychainService = "com.xiaojinpro.auth"

    private func saveCredentials(_ credentials: AuthCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKey
        ]

        // 先删除旧条目
        SecItemDelete(query as CFDictionary)

        // 添加新条目
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("⚠️ Keychain save failed: \(status)")
        }
    }

    private func loadCredentials() -> AuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let credentials = try? JSONDecoder().decode(AuthCredentials.self, from: data) else {
            if status != errSecItemNotFound {
                print("⚠️ Keychain load failed: \(status)")
            }
            return nil
        }

        return credentials
    }

    private func clearCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKey
        ]

        SecItemDelete(query as CFDictionary)
    }
}
