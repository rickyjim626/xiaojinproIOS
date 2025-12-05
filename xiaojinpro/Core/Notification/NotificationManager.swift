//
//  NotificationManager.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import Foundation
import UserNotifications
import UIKit

// MARK: - Notification Manager
@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var deviceToken: String?

    private let center = UNUserNotificationCenter.current()

    override private init() {
        super.init()
        center.delegate = self
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted

            if granted {
                await registerForRemoteNotifications()
            }

            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }

    func checkAuthorizationStatus() {
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorizationStatus = settings.authorizationStatus
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    private func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Device Token

    func handleDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = tokenString

        // Send token to server
        Task {
            await registerDeviceTokenWithServer(tokenString)
        }
    }

    func handleRegistrationError(_ error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }

    private func registerDeviceTokenWithServer(_ token: String) async {
        // TODO: Implement API call to register device token
        // try? await APIClient.shared.post(.registerDeviceToken, body: ["token": token, "platform": "ios"])
    }

    // MARK: - Local Notifications

    func scheduleTaskCompletionNotification(taskId: String, skillName: String, status: TaskStatus) {
        let content = UNMutableNotificationContent()

        switch status {
        case .succeeded:
            content.title = "任务完成"
            content.body = "\(skillName) 执行成功"
            content.sound = .default
        case .failed:
            content.title = "任务失败"
            content.body = "\(skillName) 执行失败"
            content.sound = UNNotificationSound.defaultCritical
        default:
            return
        }

        content.userInfo = [
            "type": "task_completion",
            "taskId": taskId,
            "skillName": skillName,
            "status": status.rawValue
        ]

        content.categoryIdentifier = "TASK_COMPLETION"

        let request = UNNotificationRequest(
            identifier: "task-\(taskId)",
            content: content,
            trigger: nil // Deliver immediately
        )

        center.add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }

    func scheduleReminderNotification(
        id: String,
        title: String,
        body: String,
        date: Date
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["type": "reminder", "id": id]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "reminder-\(id)",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    func cancelNotification(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: - Badge

    func setBadgeCount(_ count: Int) {
        Task { @MainActor in
            do {
                try await center.setBadgeCount(count)
            } catch {
                print("Failed to set badge count: \(error)")
            }
        }
    }

    func clearBadge() {
        setBadgeCount(0)
    }

    // MARK: - Notification Categories

    func setupNotificationCategories() {
        // Task completion category
        let viewAction = UNNotificationAction(
            identifier: "VIEW_TASK",
            title: "查看详情",
            options: .foreground
        )

        let retryAction = UNNotificationAction(
            identifier: "RETRY_TASK",
            title: "重试",
            options: []
        )

        let taskCategory = UNNotificationCategory(
            identifier: "TASK_COMPLETION",
            actions: [viewAction, retryAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        // Message category
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_MESSAGE",
            title: "回复",
            options: [],
            textInputButtonTitle: "发送",
            textInputPlaceholder: "输入回复..."
        )

        let messageCategory = UNNotificationCategory(
            identifier: "MESSAGE",
            actions: [replyAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([taskCategory, messageCategory])
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        Task { @MainActor in
            handleNotificationResponse(response, userInfo: userInfo)
        }

        completionHandler()
    }

    @MainActor
    private func handleNotificationResponse(_ response: UNNotificationResponse, userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }

        switch response.actionIdentifier {
        case "VIEW_TASK":
            if let taskId = userInfo["taskId"] as? String {
                NotificationCenter.default.post(
                    name: .navigateToTask,
                    object: nil,
                    userInfo: ["taskId": taskId]
                )
            }

        case "RETRY_TASK":
            if let taskId = userInfo["taskId"] as? String {
                Task {
                    try? await TaskService.shared.retryTask(id: taskId)
                }
            }

        case "REPLY_MESSAGE":
            if let textResponse = response as? UNTextInputNotificationResponse {
                let replyText = textResponse.userText
                // Handle reply
                print("User replied: \(replyText)")
            }

        case UNNotificationDefaultActionIdentifier:
            // User tapped on notification
            switch type {
            case "task_completion":
                if let taskId = userInfo["taskId"] as? String {
                    NotificationCenter.default.post(
                        name: .navigateToTask,
                        object: nil,
                        userInfo: ["taskId": taskId]
                    )
                }
            case "message":
                if let conversationId = userInfo["conversationId"] as? String {
                    NotificationCenter.default.post(
                        name: .navigateToConversation,
                        object: nil,
                        userInfo: ["conversationId": conversationId]
                    )
                }
            default:
                break
            }

        default:
            break
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let navigateToTask = Notification.Name("navigateToTask")
    static let navigateToConversation = Notification.Name("navigateToConversation")
}

// MARK: - Push Notification Payload
struct PushNotificationPayload: Codable {
    let type: String
    let title: String?
    let body: String?
    let data: [String: AnyCodable]?

    enum NotificationType: String, Codable {
        case taskCompletion = "task_completion"
        case newMessage = "new_message"
        case systemAlert = "system_alert"
    }
}
