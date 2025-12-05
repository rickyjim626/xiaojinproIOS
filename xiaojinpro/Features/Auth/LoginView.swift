//
//  LoginView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Logo and title
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 64))
                        .foregroundStyle(.linearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))

                    Text("xiaojinpro")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("宇宙超级终端")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                // Form
                VStack(spacing: 16) {
                    if isSignUp {
                        TextField("昵称（可选）", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)
                    }

                    TextField("邮箱", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)

                    SecureField("密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(isSignUp ? .newPassword : .password)

                    // Error message
                    if let error = authManager.error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    // Submit button
                    Button {
                        Task {
                            if isSignUp {
                                try? await authManager.signUp(
                                    email: email,
                                    password: password,
                                    name: name.isEmpty ? nil : name
                                )
                            } else {
                                try? await authManager.signIn(
                                    email: email,
                                    password: password
                                )
                            }
                        }
                    } label: {
                        Group {
                            if authManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Text(isSignUp ? "注册" : "登录")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(authManager.isLoading || !isFormValid)
                    .opacity(authManager.isLoading || !isFormValid ? 0.6 : 1.0)

                    // Toggle sign up/sign in
                    Button {
                        withAnimation {
                            isSignUp.toggle()
                            authManager.error = nil
                        }
                    } label: {
                        Text(isSignUp ? "已有账号？登录" : "没有账号？注册")
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                // Alternative login methods
                VStack(spacing: 16) {
                    Text("或使用以下方式登录")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 20) {
                        // WeChat login
                        Button {
                            Task {
                                try? await authManager.signInWithOAuth(provider: "wechat")
                            }
                        } label: {
                            Image(systemName: "message.fill")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(25)
                        }

                        // Apple login
                        AppleSignInButton()
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && password.count >= 6
    }
}

// MARK: - Apple Sign In Button
struct AppleSignInButton: View {
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        SignInWithAppleButton(
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            },
            onCompletion: { result in
                Task {
                    await handleAppleSignIn(result)
                }
            }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(width: 50, height: 50)
        .cornerRadius(25)
        .clipShape(Circle())
    }

    @MainActor
    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                await processAppleCredential(appleIDCredential)
            }
        case .failure(let error):
            authManager.error = "Apple 登录失败: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func processAppleCredential(_ credential: ASAuthorizationAppleIDCredential) async {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            authManager.error = "无法获取 Apple 身份令牌"
            return
        }

        // Get user info from credential
        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        do {
            try await authManager.signInWithApple(
                identityToken: tokenString,
                authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                email: credential.email,
                fullName: fullName.isEmpty ? nil : fullName
            )
        } catch {
            authManager.error = "Apple 登录失败: \(error.localizedDescription)"
        }
    }
}

#Preview {
    LoginView()
}
