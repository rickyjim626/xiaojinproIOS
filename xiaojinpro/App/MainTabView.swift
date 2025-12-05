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
            // Chat Tab
            ConversationsListView()
                .tabItem {
                    Label("对话", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(0)

            // Skills Tab
            SkillsView()
                .tabItem {
                    Label("能力", systemImage: "wand.and.stars")
                }
                .tag(1)

            // Admin Tab (only for admin users)
            if authManager.currentUser?.isAdmin == true {
                AdminView()
                    .tabItem {
                        Label("管理", systemImage: "gearshape.2")
                    }
                    .tag(2)
            }

            // Settings Tab
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(authManager.currentUser?.isAdmin == true ? 3 : 2)
        }
    }
}

#Preview {
    MainTabView()
}
