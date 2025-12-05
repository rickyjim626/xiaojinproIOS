//
//  APIClient.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation

// MARK: - API Configuration
enum APIConfig {
    static let authBaseURL = "https://auth.xiaojinpro.com"
    static let apiBaseURL = "https://api.xjp.dev"

    enum Endpoint {
        // Auth
        case login           // Legacy session-based login
        case loginToken      // JWT token exchange (for native apps)
        case register
        case logout
        case refreshToken
        case appleSignIn
        case userMe

        // Conversations
        case conversations
        case conversation(id: String)
        case conversationMessages(conversationId: String)

        // Skills
        case skills
        case skill(name: String)
        case executeSkill(name: String)

        // Tasks
        case tasks
        case task(id: String)
        case taskEvents(id: String)
        case taskCancel(id: String)
        case taskRetry(id: String)

        // Admin
        case servicesStatus
        case aiUsageStats
        case adminServiceRestart(service: String)

        var path: String {
            switch self {
            case .login: return "/auth/email/login"
            case .loginToken: return "/auth/email/token"
            case .register: return "/auth/email/register"
            case .logout: return "/auth/logout"
            case .refreshToken: return "/oauth2/token"
            case .appleSignIn: return "/auth/apple/signin"
            case .userMe: return "/v1/users/me"
            case .conversations: return "/ai/conversations"
            case .conversation(let id): return "/ai/conversations/\(id)"
            case .conversationMessages(let id): return "/ai/conversations/\(id)/messages"
            case .skills: return "/skills"
            case .skill(let name): return "/skills/\(name)"
            case .executeSkill(let name): return "/skills/\(name)/execute"
            case .tasks: return "/tasks"
            case .task(let id): return "/tasks/\(id)"
            case .taskEvents(let id): return "/tasks/\(id)/events"
            case .taskCancel(let id): return "/tasks/\(id)/cancel"
            case .taskRetry(let id): return "/tasks/\(id)/retry"
            case .servicesStatus: return "/admin/services/status"
            case .aiUsageStats: return "/admin/ai/usage"
            case .adminServiceRestart(let service): return "/admin/services/\(service)/restart"
            }
        }

        var baseURL: String {
            switch self {
            case .login, .loginToken, .register, .logout, .refreshToken, .appleSignIn, .userMe:
                return APIConfig.authBaseURL
            default:
                return APIConfig.apiBaseURL
            }
        }

        var url: URL {
            URL(string: baseURL + path)!
        }
    }
}

// MARK: - API Error
enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)
    case unauthorized
    case rateLimited
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            return "HTTP Error \(code): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized - please sign in again"
        case .rateLimited:
            return "Rate limited - please try again later"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// MARK: - API Response
struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: APIErrorResponse?
    let meta: APIResponseMeta?
}

struct APIErrorResponse: Decodable {
    let code: String?
    let message: String
}

struct APIResponseMeta: Decodable {
    let requestId: String?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case timestamp
    }
}

// MARK: - API Client
@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    @Published var isLoading = false

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Request Methods

    func get<T: Decodable>(
        _ endpoint: APIConfig.Endpoint,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        var urlComponents = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        return try await performRequest(request)
    }

    func post<T: Decodable, B: Encodable>(
        _ endpoint: APIConfig.Endpoint,
        body: B
    ) async throws -> T {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        return try await performRequest(request)
    }

    func delete(_ endpoint: APIConfig.Endpoint) async throws {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "DELETE"

        let _: EmptyResponse = try await performRequest(request)
    }

    // MARK: - Streaming Request

    func stream(
        _ endpoint: APIConfig.Endpoint,
        body: some Encodable
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = URLRequest(url: endpoint.url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try encoder.encode(body)

                    try await addAuthHeader(to: &request)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse
                    }

                    guard 200..<300 ~= httpResponse.statusCode else {
                        throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
                    }

                    var buffer = ""
                    for try await byte in bytes {
                        buffer.append(Character(UnicodeScalar(byte)))

                        // Parse SSE events
                        while let eventEnd = buffer.range(of: "\n\n") {
                            let eventString = String(buffer[..<eventEnd.lowerBound])
                            buffer.removeSubrange(..<eventEnd.upperBound)

                            if let event = SSEEvent.parse(eventString) {
                                continuation.yield(event)

                                if event.event == "done" {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        try await addAuthHeader(to: &request)

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, response) = try await session.data(for: request)

            // Debug: print raw response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("API Response: \(jsonString)")
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200..<300:
                do {
                    return try decoder.decode(T.self, from: data)
                } catch {
                    print("Decoding error: \(error)")
                    throw APIError.decodingError(error)
                }
            case 401:
                // Try to extract error message from response
                if let errorResponse = try? decoder.decode(ErrorOnlyResponse.self, from: data) {
                    throw APIError.httpError(statusCode: 401, message: errorResponse.message)
                }
                throw APIError.unauthorized
            case 429:
                throw APIError.rateLimited
            case 500..<600:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
                throw APIError.serverError(errorMessage)
            default:
                // Try to extract error message from response body
                if let errorResponse = try? decoder.decode(ErrorOnlyResponse.self, from: data) {
                    throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorResponse.message)
                }
                let errorMessage = String(data: data, encoding: .utf8)
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func addAuthHeader(to request: inout URLRequest) async throws {
        if let token = await AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

// MARK: - Empty Response
struct EmptyResponse: Decodable {}

// MARK: - Error Only Response (for parsing error messages from API)
struct ErrorOnlyResponse: Decodable {
    let error: String?
    let message: String
}
