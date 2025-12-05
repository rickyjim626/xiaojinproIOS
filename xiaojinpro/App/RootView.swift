//
//  RootView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI

struct RootView: View {
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        Group {
            switch authManager.state {
            case .unknown:
                // Loading state
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 64))
                        .foregroundStyle(.linearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))

                    ProgressView()

                    Text("加载中...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .authenticated:
                MainTabView()

            case .unauthenticated:
                LoginView()
            }
        }
        .animation(.easeInOut, value: authManager.state)
    }
}

#Preview {
    RootView()
}
