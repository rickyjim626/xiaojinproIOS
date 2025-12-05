//
//  xiaojinproApp.swift
//  xiaojinpro
//
//  Created by 靳晨 on 2025/12/5.
//

import SwiftUI

@main
struct xiaojinproApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var storage = LocalStorage.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared

    init() {
        // Configure app appearance
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(storage)
                .environmentObject(networkMonitor)
                .preferredColorScheme(storage.isDarkMode ? .dark : nil)
                .onReceive(NotificationCenter.default.publisher(for: .navigateToTask)) { notification in
                    handleTaskNavigation(notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToConversation)) { notification in
                    handleConversationNavigation(notification)
                }
        }
    }

    private func configureAppearance() {
        // Configure navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance

        // Configure tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    private func handleTaskNavigation(_ notification: Notification) {
        // Handle navigation to task detail
        if let taskId = notification.userInfo?["taskId"] as? String {
            // Navigate to task - this would typically update some app state
            print("Navigate to task: \(taskId)")
        }
    }

    private func handleConversationNavigation(_ notification: Notification) {
        // Handle navigation to conversation
        if let conversationId = notification.userInfo?["conversationId"] as? String {
            print("Navigate to conversation: \(conversationId)")
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Setup notification categories
        Task { @MainActor in
            NotificationManager.shared.setupNotificationCategories()
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleRegistrationError(error)
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Clear badge when entering foreground
        Task { @MainActor in
            NotificationManager.shared.clearBadge()
        }
    }
}
