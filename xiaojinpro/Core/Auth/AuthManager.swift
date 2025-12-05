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
struct User: Codable, Identifiable, Equatable {
    let id: String
    let email: String?
    let name: String?
    let avatarUrl: String?
    let subscriptionTier: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case avatarUrl = "avatar_url"
        case subscriptionTier = "subscription_tier"
        case createdAt = "created_at"
    }

    var displayName: String {
        name ?? email ?? "User"
    }

    var isAdmin: Bool {
        subscriptionTier == "studio" || subscriptionTier == "admin"
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
struct AuthCredentials: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
}

// MARK: - Login Request/Response
struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct RegisterRequest: Codable {
    let email: String
    let password: String
    let name: String?
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let user: User?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

// MARK: - OAuth Token Request
struct OAuthTokenRequest: Codable {
    let grantType: String
    let code: String
    let redirectUri: String
    let provider: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case code
        case redirectUri = "redirect_uri"
        case provider
    }
}

// MARK: - Apple Sign In Request
struct AppleSignInRequest: Codable {
    let identityToken: String
    let authorizationCode: String?
    let email: String?
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
        case email
        case fullName = "full_name"
    }
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
            let request = LoginRequest(email: email, password: password)
            let response: AuthResponse = try await APIClient.shared.post(.login, body: request)

            let credentials = AuthCredentials(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
            )

            saveCredentials(credentials)

            // Fetch user info if not included in response
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

    private func saveCredentials(_ credentials: AuthCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadCredentials() -> AuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let credentials = try? JSONDecoder().decode(AuthCredentials.self, from: data) else {
            return nil
        }

        return credentials
    }

    private func clearCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]

        SecItemDelete(query as CFDictionary)
    }
}
