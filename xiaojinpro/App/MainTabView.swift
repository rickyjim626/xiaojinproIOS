//
//  MainTabView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // AI Chat - 所有用户的主功能
            AIChatHomeView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }
                .tag(0)

            // Admin 用户可以访问控制台
            if authManager.currentUser?.isAdmin == true {
                ConsoleView()
                    .tabItem {
                        Label("控制台", systemImage: "globe.asia.australia")
                    }
                    .tag(1)
            }

            // 设置
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(authManager.currentUser?.isAdmin == true ? 2 : 1)
        }
    }
}

#Preview {
    MainTabView()
}
