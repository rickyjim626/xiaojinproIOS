//
//  SettingsView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var storage = LocalStorage.shared
    @State private var showingLogoutAlert = false
    @State private var showingResetAlert = false

    var body: some View {
        NavigationStack {
            List {
                // User section
                if let user = authManager.currentUser {
                    Section {
                        HStack(spacing: 12) {
                            // Avatar
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 60, height: 60)
                                .overlay {
                                    if let avatarUrl = user.avatarUrl,
                                       let url = URL(string: avatarUrl) {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Image(systemName: "person.fill")
                                                .font(.title)
                                                .foregroundColor(.blue)
                                        }
                                        .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.fill")
                                            .font(.title)
                                            .foregroundColor(.blue)
                                    }
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline)

                                if let email = user.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if let tier = user.subscriptionTier {
                                    Text(tierDisplayName(tier))
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(tierColor(tier).opacity(0.2))
                                        .foregroundColor(tierColor(tier))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // General settings
                Section("通用") {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("外观", systemImage: "paintbrush")
                    }

                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("通知", systemImage: "bell")
                    }

                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        Label("语言", systemImage: "globe")
                    }
                }

                // AI settings
                Section("AI") {
                    NavigationLink {
                        AIModelSettingsView()
                    } label: {
                        HStack {
                            Label("默认模型", systemImage: "brain")
                            Spacer()
                            Text(storage.defaultModel.split(separator: "-").first.map(String.init) ?? "Claude")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $storage.streamingEnabled) {
                        Label("流式响应", systemImage: "waveform")
                    }
                }

                // Cache management
                Section("缓存") {
                    Button {
                        storage.clearCache()
                    } label: {
                        Label("清除缓存", systemImage: "trash")
                    }

                    if let lastSync = storage.lastSyncTime {
                        HStack {
                            Label("上次同步", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            Text(lastSync.relativeString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // About
                Section("关于") {
                    HStack {
                        Label("版本", systemImage: "info.circle")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }

                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("隐私政策", systemImage: "hand.raised")
                    }

                    NavigationLink {
                        TermsOfServiceView()
                    } label: {
                        Label("服务条款", systemImage: "doc.text")
                    }

                    Link(destination: URL(string: "https://github.com/rickyjim626/xiaojinproIOS")!) {
                        HStack {
                            Label("GitHub", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Account actions
                Section {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("重置所有设置", systemImage: "arrow.counterclockwise")
                    }

                    if authManager.state.isAuthenticated {
                        Button(role: .destructive) {
                            showingLogoutAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("退出登录")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .alert("确认退出", isPresented: $showingLogoutAlert) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) {
                    Task {
                        await authManager.signOut()
                    }
                }
            } message: {
                Text("确定要退出登录吗？")
            }
            .alert("重置设置", isPresented: $showingResetAlert) {
                Button("取消", role: .cancel) {}
                Button("重置", role: .destructive) {
                    storage.resetToDefaults()
                }
            } message: {
                Text("这将重置所有设置为默认值，确定吗？")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func tierDisplayName(_ tier: String) -> String {
        switch tier {
        case "free": return "免费版"
        case "creator_beta": return "创作者"
        case "studio": return "工作室"
        case "admin": return "管理员"
        default: return tier
        }
    }

    private func tierColor(_ tier: String) -> Color {
        switch tier {
        case "free": return .gray
        case "creator_beta": return .blue
        case "studio": return .purple
        case "admin": return .red
        default: return .gray
        }
    }
}

// MARK: - Appearance Settings
struct AppearanceSettingsView: View {
    @StateObject private var storage = LocalStorage.shared
    @Environment(\.colorScheme) var systemColorScheme

    var body: some View {
        List {
            Section {
                Toggle("深色模式", isOn: $storage.isDarkMode)
            } footer: {
                Text("开启后将使用深色主题，关闭则跟随系统设置")
            }

            Section("主题预览") {
                HStack(spacing: 16) {
                    ThemePreviewCard(isDark: false, isSelected: !storage.isDarkMode)
                        .onTapGesture { storage.isDarkMode = false }

                    ThemePreviewCard(isDark: true, isSelected: storage.isDarkMode)
                        .onTapGesture { storage.isDarkMode = true }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ThemePreviewCard: View {
    let isDark: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isDark ? Color.black : Color.white)
                .frame(height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                )
                .overlay {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isDark ? Color.gray : Color.gray.opacity(0.3))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isDark ? Color.gray : Color.gray.opacity(0.3))
                            .frame(width: 60, height: 12)
                    }
                    .padding()
                }

            Text(isDark ? "深色" : "浅色")
                .font(.caption)
                .foregroundColor(isSelected ? .blue : .secondary)
        }
    }
}

// MARK: - Notification Settings
struct NotificationSettingsView: View {
    @StateObject private var storage = LocalStorage.shared
    @State private var taskCompleteNotification = true
    @State private var messageNotification = true
    @State private var systemNotification = true

    var body: some View {
        List {
            Section {
                Toggle("启用通知", isOn: $storage.notificationsEnabled)
            } footer: {
                Text("关闭后将不会收到任何推送通知")
            }

            if storage.notificationsEnabled {
                Section("通知类型") {
                    Toggle("任务完成", isOn: $taskCompleteNotification)
                    Toggle("新消息", isOn: $messageNotification)
                    Toggle("系统通知", isOn: $systemNotification)
                }
            }
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Language Settings
struct LanguageSettingsView: View {
    @StateObject private var storage = LocalStorage.shared

    let languages = [
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("en", "English"),
        ("ja", "日本語")
    ]

    var body: some View {
        List {
            Section {
                ForEach(languages, id: \.0) { code, name in
                    Button {
                        storage.preferredLanguage = code
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundColor(.primary)
                            Spacer()
                            if storage.preferredLanguage == code {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } footer: {
                Text("更改语言后可能需要重启应用才能生效")
            }
        }
        .navigationTitle("语言")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AI Model Settings
struct AIModelSettingsView: View {
    @StateObject private var storage = LocalStorage.shared

    let models = [
        ("claude-sonnet-4-20250514", "Claude Sonnet 4", "平衡速度和质量"),
        ("claude-opus-4-20250514", "Claude Opus 4", "最强能力，较慢"),
        ("claude-3-5-haiku-20241022", "Claude 3.5 Haiku", "最快速度，适合简单任务")
    ]

    var body: some View {
        List {
            Section("默认模型") {
                ForEach(models, id: \.0) { id, name, description in
                    Button {
                        storage.defaultModel = id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name)
                                    .foregroundColor(.primary)
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if storage.defaultModel == id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }

            Section("高级设置") {
                Toggle("流式响应", isOn: $storage.streamingEnabled)

                Stepper("最大 Tokens: \(storage.maxTokens)", value: $storage.maxTokens, in: 1024...16384, step: 1024)
            }
        }
        .navigationTitle("AI 设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Privacy Policy View
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("隐私政策")
                    .font(.title)
                    .fontWeight(.bold)

                Text("最后更新: 2025年1月1日")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Group {
                    SectionHeader("信息收集")
                    Text("我们收集您在使用 xiaojinpro 时提供的信息，包括：")
                    BulletPoint("账户信息（邮箱、用户名）")
                    BulletPoint("对话内容（用于 AI 处理）")
                    BulletPoint("使用数据（功能使用统计）")

                    SectionHeader("信息使用")
                    Text("我们使用收集的信息来：")
                    BulletPoint("提供和改进服务")
                    BulletPoint("处理您的 AI 请求")
                    BulletPoint("发送服务通知")

                    SectionHeader("数据安全")
                    Text("我们采取适当的技术措施保护您的个人信息，包括加密传输和安全存储。")

                    SectionHeader("联系我们")
                    Text("如有任何隐私相关问题，请联系 privacy@xiaojinpro.com")
                }
            }
            .padding()
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Terms of Service View
struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("服务条款")
                    .font(.title)
                    .fontWeight(.bold)

                Text("最后更新: 2025年1月1日")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Group {
                    SectionHeader("服务说明")
                    Text("xiaojinpro 是一个 AI 驱动的超级终端，提供智能对话、技能执行和系统管理功能。")

                    SectionHeader("使用规范")
                    Text("使用本服务时，您同意：")
                    BulletPoint("不进行任何非法活动")
                    BulletPoint("不滥用 AI 功能")
                    BulletPoint("不侵犯他人权益")
                    BulletPoint("遵守所有适用法律法规")

                    SectionHeader("免责声明")
                    Text("AI 生成的内容仅供参考，我们不对其准确性、完整性或适用性作出保证。")

                    SectionHeader("服务变更")
                    Text("我们保留随时修改、暂停或终止服务的权利。重大变更将提前通知用户。")
                }
            }
            .padding()
        }
        .navigationTitle("服务条款")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helper Views
struct SectionHeader: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.headline)
            .padding(.top, 8)
    }
}

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.body)
    }
}

#Preview {
    SettingsView()
}
