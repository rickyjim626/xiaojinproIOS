//
//  ConsoleView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI

// MARK: - Console Home View (Admin Backend)
struct ConsoleView: View {
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        NavigationStack {
            List {
                // Header Section
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "globe.asia.australia.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("xiaojinpro 宇宙")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("管理控制台")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                // AI 对话管理
                Section("AI 服务") {
                    NavigationLink {
                        ConversationsListView()
                    } label: {
                        ConsoleMenuRow(
                            icon: "bubble.left.and.bubble.right.fill",
                            iconColor: .blue,
                            title: "智能对话",
                            subtitle: "多轮对话 · 工具调用 · 工作流"
                        )
                    }

                    NavigationLink {
                        SkillsView()
                    } label: {
                        ConsoleMenuRow(
                            icon: "wand.and.stars",
                            iconColor: .purple,
                            title: "能力中心",
                            subtitle: "技能管理 · 执行记录"
                        )
                    }

                    NavigationLink {
                        TasksView()
                    } label: {
                        ConsoleMenuRow(
                            icon: "checklist",
                            iconColor: .orange,
                            title: "任务队列",
                            subtitle: "异步任务 · 执行状态"
                        )
                    }
                }

                // 系统管理
                Section("系统管理") {
                    NavigationLink {
                        AdminView()
                    } label: {
                        ConsoleMenuRow(
                            icon: "server.rack",
                            iconColor: .red,
                            title: "服务监控",
                            subtitle: "服务状态 · AI 用量 · 系统指标"
                        )
                    }

                    NavigationLink {
                        UsageStatsView()
                    } label: {
                        ConsoleMenuRow(
                            icon: "chart.bar.fill",
                            iconColor: .green,
                            title: "使用统计",
                            subtitle: "Token 用量 · 调用次数"
                        )
                    }
                }

                // 用户信息
                Section("当前用户") {
                    if let user = authManager.currentUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.headline)

                                Text(user.email ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text("Admin")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .cornerRadius(6)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("控制台")
        }
    }
}

// MARK: - Console Menu Row
struct ConsoleMenuRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(iconColor)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Usage Stats View (Placeholder)
struct UsageStatsView: View {
    var body: some View {
        List {
            Section("本月用量") {
                StatRow(title: "总 Token 数", value: "125,430", trend: "+12%")
                StatRow(title: "API 调用次数", value: "1,234", trend: "+8%")
                StatRow(title: "对话数", value: "89", trend: "+15%")
            }

            Section("模型分布") {
                ModelUsageRow(model: "Claude Sonnet 4.5", percentage: 65)
                ModelUsageRow(model: "Claude Opus 4.1", percentage: 25)
                ModelUsageRow(model: "Gemini 3 Pro", percentage: 10)
            }
        }
        .navigationTitle("使用统计")
    }
}

struct StatRow: View {
    let title: String
    let value: String
    let trend: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.semibold)

            Text(trend)
                .font(.caption)
                .foregroundColor(trend.hasPrefix("+") ? .green : .red)
        }
    }
}

struct ModelUsageRow: View {
    let model: String
    let percentage: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model)
                Spacer()
                Text("\(percentage)%")
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(percentage) / 100)
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ConsoleView()
}
