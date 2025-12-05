//
//  AdminView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI

struct AdminView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom tab bar
                HStack(spacing: 0) {
                    AdminTabButton(
                        title: "服务",
                        icon: "server.rack",
                        isSelected: selectedTab == 0
                    ) { selectedTab = 0 }

                    AdminTabButton(
                        title: "任务",
                        icon: "list.bullet",
                        isSelected: selectedTab == 1
                    ) { selectedTab = 1 }

                    AdminTabButton(
                        title: "统计",
                        icon: "chart.bar",
                        isSelected: selectedTab == 2
                    ) { selectedTab = 2 }

                    AdminTabButton(
                        title: "Console",
                        icon: "terminal",
                        isSelected: selectedTab == 3
                    ) { selectedTab = 3 }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .background(Color(.systemBackground))

                Divider()

                // Content
                TabView(selection: $selectedTab) {
                    ServicesStatusView()
                        .tag(0)

                    TaskQueueView()
                        .tag(1)

                    AIUsageView()
                        .tag(2)

                    AdminConsoleView()
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("管理终端")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Admin Tab Button
struct AdminTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? .blue : .secondary)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Admin Service
@MainActor
class AdminService: ObservableObject {
    static let shared = AdminService()

    @Published var services: [ServiceStatus] = []
    @Published var usageStats: UsageStats?
    @Published var isLoadingServices = false
    @Published var isLoadingStats = false
    @Published var error: String?

    func fetchServices() async {
        isLoadingServices = true
        error = nil

        do {
            let response: ServicesResponse = try await APIClient.shared.get(.servicesStatus)
            services = response.services
        } catch {
            self.error = error.localizedDescription
            // Use placeholder data for now
            services = [
                ServiceStatus(name: "AIRouter", description: "AI 模型路由服务", status: .online, metrics: ServiceMetrics(cpu: 15, memory: 45, requests: 1234)),
                ServiceStatus(name: "Auth", description: "认证授权服务", status: .online, metrics: ServiceMetrics(cpu: 8, memory: 30, requests: 567)),
                ServiceStatus(name: "Timeline", description: "时间线编辑服务", status: .online, metrics: ServiceMetrics(cpu: 22, memory: 55, requests: 890)),
                ServiceStatus(name: "ASR", description: "语音识别服务", status: .degraded, metrics: ServiceMetrics(cpu: 65, memory: 80, requests: 123)),
            ]
        }

        isLoadingServices = false
    }

    func restartService(_ serviceName: String) async throws {
        let _: EmptyResponse = try await APIClient.shared.post(.adminServiceRestart(service: serviceName), body: EmptyBody())
    }

    func fetchUsageStats(period: String) async {
        isLoadingStats = true

        do {
            let response: UsageStats = try await APIClient.shared.get(.aiUsageStats, queryItems: [
                URLQueryItem(name: "period", value: period)
            ])
            usageStats = response
        } catch {
            // Use placeholder data
            usageStats = UsageStats(
                totalRequests: 12345,
                successfulRequests: 12000,
                failedRequests: 345,
                totalTokens: 5_678_900,
                promptTokens: 4_000_000,
                completionTokens: 1_678_900,
                totalCost: 12.5678
            )
        }

        isLoadingStats = false
    }
}

// MARK: - Services Response
struct ServicesResponse: Codable {
    let services: [ServiceStatus]
}

struct EmptyBody: Codable {}

// MARK: - Services Status View
struct ServicesStatusView: View {
    @StateObject private var adminService = AdminService.shared
    @State private var selectedService: ServiceStatus?
    @State private var showingRestartConfirmation = false
    @State private var serviceToRestart: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary cards
                HStack(spacing: 12) {
                    ServiceSummaryCard(
                        title: "在线",
                        count: adminService.services.filter { $0.status == .online }.count,
                        icon: "checkmark.circle.fill",
                        color: .green
                    )

                    ServiceSummaryCard(
                        title: "降级",
                        count: adminService.services.filter { $0.status == .degraded }.count,
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )

                    ServiceSummaryCard(
                        title: "离线",
                        count: adminService.services.filter { $0.status == .offline }.count,
                        icon: "xmark.circle.fill",
                        color: .red
                    )
                }
                .padding(.horizontal)

                // Services list
                VStack(spacing: 12) {
                    ForEach(adminService.services) { service in
                        ServiceCard(
                            service: service,
                            onRestart: {
                                serviceToRestart = service.name
                                showingRestartConfirmation = true
                            },
                            onTap: {
                                selectedService = service
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .refreshable {
            await adminService.fetchServices()
        }
        .task {
            await adminService.fetchServices()
        }
        .sheet(item: $selectedService) { service in
            ServiceDetailSheet(service: service)
        }
        .alert("确认重启", isPresented: $showingRestartConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重启", role: .destructive) {
                if let name = serviceToRestart {
                    Task {
                        try? await adminService.restartService(name)
                        await adminService.fetchServices()
                    }
                }
            }
        } message: {
            Text("确定要重启 \(serviceToRestart ?? "") 服务吗？")
        }
    }
}

// MARK: - Service Summary Card
struct ServiceSummaryCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)

            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Service Card
struct ServiceCard: View {
    let service: ServiceStatus
    let onRestart: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // Status indicator
                    Circle()
                        .fill(service.status.color)
                        .frame(width: 12, height: 12)

                    Text(service.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    // Status badge
                    Text(service.status.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(service.status.color.opacity(0.2))
                        .foregroundColor(service.status.color)
                        .cornerRadius(4)

                    // Restart button
                    Button(action: onRestart) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }

                Text(service.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let metrics = service.metrics {
                    Divider()

                    HStack(spacing: 16) {
                        MetricView(label: "CPU", value: metrics.cpu, unit: "%", color: metricColor(metrics.cpu))
                        MetricView(label: "内存", value: metrics.memory, unit: "%", color: metricColor(metrics.memory))
                        MetricView(label: "请求/分", value: metrics.requests, unit: "", color: .blue)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func metricColor(_ value: Int) -> Color {
        if value >= 80 { return .red }
        if value >= 60 { return .orange }
        return .green
    }
}

// MARK: - Metric View
struct MetricView: View {
    let label: String
    let value: Int
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text("\(value)")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(unit)
                    .font(.caption)
            }
            .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Service Detail Sheet
struct ServiceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let service: ServiceStatus

    var body: some View {
        NavigationStack {
            List {
                Section("基本信息") {
                    LabeledContent("服务名称", value: service.name)
                    LabeledContent("状态", value: service.status.displayName)
                    LabeledContent("描述", value: service.description)
                }

                if let metrics = service.metrics {
                    Section("性能指标") {
                        LabeledContent("CPU 使用率", value: "\(metrics.cpu)%")
                        LabeledContent("内存使用率", value: "\(metrics.memory)%")
                        LabeledContent("请求数/分钟", value: "\(metrics.requests)")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        // Restart action
                    } label: {
                        Label("重启服务", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle(service.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Service Status Model
struct ServiceStatus: Identifiable, Codable {
    var id: String { name }
    let name: String
    let description: String
    let status: Status
    let metrics: ServiceMetrics?

    enum Status: String, Codable {
        case online, degraded, offline

        var color: Color {
            switch self {
            case .online: return .green
            case .degraded: return .orange
            case .offline: return .red
            }
        }

        var displayName: String {
            switch self {
            case .online: return "正常"
            case .degraded: return "降级"
            case .offline: return "离线"
            }
        }
    }
}

struct ServiceMetrics: Codable {
    let cpu: Int
    let memory: Int
    let requests: Int
}

// MARK: - Task Queue View
struct TaskQueueView: View {
    @StateObject private var service = TaskService.shared
    @State private var filter = TaskFilter()
    @State private var selectedStatus: TaskStatus?
    @State private var showingFilterSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Stats bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    TaskStatChip(
                        title: "全部",
                        count: service.tasks.count,
                        color: .gray,
                        isSelected: selectedStatus == nil
                    ) { selectedStatus = nil }

                    TaskStatChip(
                        title: "等待",
                        count: service.pendingCount,
                        color: .gray,
                        isSelected: selectedStatus == .pending
                    ) { selectedStatus = .pending }

                    TaskStatChip(
                        title: "运行",
                        count: service.runningCount,
                        color: .blue,
                        isSelected: selectedStatus == .running
                    ) { selectedStatus = .running }

                    TaskStatChip(
                        title: "成功",
                        count: service.tasks.filter { $0.status == .succeeded }.count,
                        color: .green,
                        isSelected: selectedStatus == .succeeded
                    ) { selectedStatus = .succeeded }

                    TaskStatChip(
                        title: "失败",
                        count: service.failedCount,
                        color: .red,
                        isSelected: selectedStatus == .failed
                    ) { selectedStatus = .failed }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .background(Color(.systemGray6))

            // Task list
            List {
                if service.isLoading && service.tasks.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if filteredTasks.isEmpty {
                    ContentUnavailableView {
                        Label("暂无任务", systemImage: "tray")
                    } description: {
                        Text("没有符合条件的任务")
                    }
                } else {
                    ForEach(filteredTasks) { task in
                        EnhancedTaskRow(task: task, onRetry: {
                            Task { try? await service.retryTask(id: task.id) }
                        }, onCancel: {
                            Task { try? await service.cancelTask(id: task.id) }
                        })
                    }
                }
            }
            .listStyle(.plain)
        }
        .refreshable {
            await service.fetchTasks(filter: filter)
        }
        .task {
            await service.fetchTasks(filter: filter)
        }
    }

    private var filteredTasks: [XJPTask] {
        if let status = selectedStatus {
            return service.tasks.filter { $0.status == status }
        }
        return service.tasks
    }
}

// MARK: - Task Stat Chip
struct TaskStatChip: View {
    let title: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.15) : Color(.systemBackground))
            .foregroundColor(isSelected ? color : .primary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Enhanced Task Row
struct EnhancedTaskRow: View {
    let task: XJPTask
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Status icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 36, height: 36)

                    if task.status == .running {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: task.status.icon)
                            .foregroundColor(statusColor)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.skillName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        Text(task.createdFrom.rawValue.uppercased())
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)

                        Text(task.createdAt.relativeString)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let duration = task.formattedDuration {
                            Text("(\(duration))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Actions
                if task.status == .failed {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                } else if task.status == .running || task.status == .pending {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Progress bar for running tasks
            if task.status == .running, let progress = task.progress {
                ProgressView(value: Double(progress), total: 100)
                    .progressViewStyle(.linear)
            }

            // Error message
            if let error = task.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch task.status {
        case .pending: return .gray
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

// MARK: - AI Usage View
struct AIUsageView: View {
    @StateObject private var adminService = AdminService.shared
    @State private var period = "today"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Period picker
                Picker("周期", selection: $period) {
                    Text("今天").tag("today")
                    Text("本周").tag("week")
                    Text("本月").tag("month")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if let stats = adminService.usageStats {
                    // Summary cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        UsageSummaryCard(
                            title: "总请求",
                            value: formatNumber(stats.totalRequests),
                            icon: "arrow.left.arrow.right",
                            color: .blue
                        )

                        UsageSummaryCard(
                            title: "成功率",
                            value: String(format: "%.1f%%", Double(stats.successfulRequests) / Double(stats.totalRequests) * 100),
                            icon: "checkmark.circle",
                            color: .green
                        )

                        UsageSummaryCard(
                            title: "总 Token",
                            value: formatNumber(stats.totalTokens),
                            icon: "textformat.abc",
                            color: .purple
                        )

                        UsageSummaryCard(
                            title: "总费用",
                            value: "$\(String(format: "%.2f", stats.totalCost))",
                            icon: "dollarsign.circle",
                            color: .orange
                        )
                    }
                    .padding(.horizontal)

                    // Detailed stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("详细统计")
                            .font(.headline)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            UsageStatRow(label: "成功请求", value: formatNumber(stats.successfulRequests), color: .green)
                            Divider()
                            UsageStatRow(label: "失败请求", value: formatNumber(stats.failedRequests), color: .red)
                            Divider()
                            UsageStatRow(label: "输入 Token", value: formatNumber(stats.promptTokens), color: nil)
                            Divider()
                            UsageStatRow(label: "输出 Token", value: formatNumber(stats.completionTokens), color: nil)
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Cost breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("费用明细")
                            .font(.headline)
                            .padding(.horizontal, 4)

                        VStack(spacing: 12) {
                            CostBar(
                                label: "输入 Token",
                                cost: stats.totalCost * 0.3,
                                percentage: 30,
                                color: .blue
                            )
                            CostBar(
                                label: "输出 Token",
                                cost: stats.totalCost * 0.7,
                                percentage: 70,
                                color: .purple
                            )
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                } else if adminService.isLoadingStats {
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .frame(height: 300)
                }
            }
            .padding(.vertical)
        }
        .task {
            await adminService.fetchUsageStats(period: period)
        }
        .onChange(of: period) { _, newPeriod in
            Task { await adminService.fetchUsageStats(period: newPeriod) }
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}

// MARK: - Usage Summary Card
struct UsageSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Usage Stat Row
struct UsageStatRow: View {
    let label: String
    let value: String
    let color: Color?

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(color ?? .primary)
        }
        .padding()
    }
}

// MARK: - Cost Bar
struct CostBar: View {
    let label: String
    let cost: Double
    let percentage: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("$\(String(format: "%.4f", cost))")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(percentage) / 100, height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Usage Stats Model
struct UsageStats: Codable {
    let totalRequests: Int
    let successfulRequests: Int
    let failedRequests: Int
    let totalTokens: Int
    let promptTokens: Int
    let completionTokens: Int
    let totalCost: Double

    enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests"
        case successfulRequests = "successful_requests"
        case failedRequests = "failed_requests"
        case totalTokens = "total_tokens"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalCost = "total_cost"
    }
}

// MARK: - Admin Console View
struct AdminConsoleView: View {
    @StateObject private var store: ConversationStore

    init() {
        let conversation = Conversation(
            id: "admin-console",
            tenantId: nil,
            type: .admin,
            title: "管理控制台",
            systemPrompt: """
            你是 xiaojinpro 宇宙的管理助手。你可以帮助用户：
            - 查看和管理服务状态
            - 查询任务队列和失败记录
            - 调整系统配置
            - 查看 AI 使用统计
            请使用提供的工具来执行管理操作。回答要简洁专业。
            """,
            createdAt: Date(),
            updatedAt: Date()
        )
        _store = StateObject(wrappedValue: ConversationStore(conversation: conversation))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Quick actions bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    QuickActionButton(title: "服务状态", icon: "server.rack") {
                        store.send("查看所有服务的当前状态")
                    }

                    QuickActionButton(title: "失败任务", icon: "exclamationmark.triangle") {
                        store.send("列出最近失败的任务")
                    }

                    QuickActionButton(title: "使用统计", icon: "chart.bar") {
                        store.send("查看今天的 AI 使用统计")
                    }

                    QuickActionButton(title: "系统健康", icon: "heart") {
                        store.send("检查系统整体健康状况")
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray6))

            // Chat view
            ChatView(store: store)
        }
    }
}

// MARK: - Quick Action Button
struct QuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AdminView()
}
