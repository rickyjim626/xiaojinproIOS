//
//  TasksView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI

// MARK: - Tasks List View
struct TasksView: View {
    @StateObject private var taskService = TaskService.shared
    @State private var selectedTask: XJPTask?
    @State private var filterStatus: TaskStatus?

    var filteredTasks: [XJPTask] {
        if let status = filterStatus {
            return taskService.tasks.filter { $0.status == status }
        }
        return taskService.tasks
    }

    var body: some View {
        NavigationStack {
            Group {
                if taskService.isLoading && taskService.tasks.isEmpty {
                    LoadingView()
                } else if taskService.tasks.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "暂无任务",
                        message: "执行技能后会产生异步任务"
                    )
                } else {
                    tasksList
                }
            }
            .navigationTitle("任务队列")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            filterStatus = nil
                        } label: {
                            Label("全部", systemImage: filterStatus == nil ? "checkmark" : "")
                        }

                        ForEach([TaskStatus.pending, .running, .succeeded, .failed], id: \.self) { status in
                            Button {
                                filterStatus = status
                            } label: {
                                Label(status.displayName, systemImage: filterStatus == status ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable {
                try? await taskService.fetchTasks()
            }
            .navigationDestination(item: $selectedTask) { task in
                TaskDetailView(taskId: task.id)
            }
        }
        .task {
            try? await taskService.fetchTasks()
        }
    }

    private var tasksList: some View {
        List {
            ForEach(filteredTasks) { task in
                TaskRow(task: task)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTask = task
                    }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Task Row
struct TaskRow: View {
    let task: XJPTask

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 44, height: 44)

                if task.status == .running {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: task.status.icon)
                        .foregroundColor(statusColor)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(task.skillName)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(task.status.displayName)
                        .font(.caption)
                        .foregroundColor(statusColor)

                    Text(task.createdAt.shortString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
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

// MARK: - Task Detail View
struct TaskDetailView: View {
    let taskId: String
    @StateObject private var viewModel: TaskDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(taskId: String) {
        self.taskId = taskId
        _viewModel = StateObject(wrappedValue: TaskDetailViewModel(taskId: taskId))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let task = viewModel.task {
                    // Status card
                    taskStatusCard(task)

                    // Info card
                    taskInfoCard(task)

                    // Arguments card
                    if let args = task.arguments, !args.isEmpty {
                        argumentsCard(args)
                    }

                    // Result card
                    if task.status == .succeeded, let result = task.result {
                        resultCard(result)
                    }

                    // Error card
                    if let error = task.error {
                        errorCard(error)
                    }

                    // Logs card
                    if !viewModel.logs.isEmpty {
                        logsCard
                    }

                    // Actions
                    actionsSection(task)

                } else if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .frame(height: 300)
                } else if let error = viewModel.error {
                    ErrorView(
                        error: error,
                        retryAction: { Task { await viewModel.loadTask() } }
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("任务详情")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.loadTask()
        }
        .task {
            await viewModel.loadTask()
        }
    }

    private func taskStatusCard(_ task: XJPTask) -> some View {
        VStack(spacing: 16) {
            HStack {
                // Status icon
                ZStack {
                    Circle()
                        .fill(statusColor(task.status).opacity(0.2))
                        .frame(width: 60, height: 60)

                    if task.status == .running {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: task.status.icon)
                            .font(.title)
                            .foregroundColor(statusColor(task.status))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.status.displayName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(task.skillName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let duration = task.formattedDuration {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(duration)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                        Text("耗时")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Progress bar
            if task.status == .running {
                VStack(alignment: .leading, spacing: 4) {
                    if let message = task.progressMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let progress = task.progress {
                        ProgressView(value: Double(progress), total: 100)
                            .progressViewStyle(.linear)
                        HStack {
                            Spacer()
                            Text("\(progress)%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func taskInfoCard(_ task: XJPTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("任务信息")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "任务 ID", value: task.id)
                Divider()
                InfoRow(label: "技能名称", value: task.skillName)
                Divider()
                InfoRow(label: "来源", value: task.createdFrom.rawValue.uppercased())
                Divider()
                InfoRow(label: "创建时间", value: task.createdAt.shortString)
                if let startedAt = task.startedAt {
                    Divider()
                    InfoRow(label: "开始时间", value: startedAt.shortString)
                }
                if let completedAt = task.completedAt {
                    Divider()
                    InfoRow(label: "完成时间", value: completedAt.shortString)
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func argumentsCard(_ args: [String: AnyCodable]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("执行参数")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(args.keys.sorted()), id: \.self) { key in
                    if let index = Array(args.keys.sorted()).firstIndex(of: key), index > 0 {
                        Divider()
                    }
                    InfoRow(label: key, value: formatValue(args[key]?.value))
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func resultCard(_ result: AnyCodable) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("执行结果")
                    .font(.headline)

                Spacer()

                Button {
                    UIPasteboard.general.string = formatJSON(result.value)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.caption)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(formatJSON(result.value))
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("错误信息")
                    .font(.headline)
            }

            Text(error)
                .font(.subheadline)
                .foregroundColor(.red)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("执行日志")
                    .font(.headline)

                Spacer()

                Text("\(viewModel.logs.count) 条")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.logs) { log in
                    LogEntryRow(log: log)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func actionsSection(_ task: XJPTask) -> some View {
        VStack(spacing: 12) {
            if task.status == .failed {
                Button {
                    Task { await viewModel.retryTask() }
                } label: {
                    Label("重试任务", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if task.status == .running || task.status == .pending {
                Button(role: .destructive) {
                    Task { await viewModel.cancelTask() }
                } label: {
                    Label("取消任务", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private func formatValue(_ value: Any?) -> String {
        guard let value = value else { return "-" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let bool = value as? Bool { return bool ? "是" : "否" }
        if let array = value as? [Any] { return array.map { "\($0)" }.joined(separator: ", ") }
        return String(describing: value)
    }

    private func formatJSON(_ value: Any) -> String {
        if let dict = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Log Entry Row
struct LogEntryRow: View {
    let log: TaskLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(logColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(log.message)
                    .font(.caption)

                Text(log.timestamp.shortString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var logColor: Color {
        switch log.level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return .gray
        }
    }
}

// MARK: - Task Detail ViewModel
@MainActor
class TaskDetailViewModel: ObservableObject {
    let taskId: String

    @Published var task: XJPTask?
    @Published var logs: [TaskLogEntry] = []
    @Published var isLoading = false
    @Published var error: String?

    private let taskService = TaskService.shared

    init(taskId: String) {
        self.taskId = taskId
    }

    func loadTask() async {
        isLoading = true
        error = nil

        do {
            task = try await taskService.fetchTask(id: taskId)
            // Load logs if available
            // logs = try await taskService.fetchTaskLogs(id: taskId)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func retryTask() async {
        do {
            task = try await taskService.retryTask(id: taskId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func cancelTask() async {
        do {
            try await taskService.cancelTask(id: taskId)
            await loadTask()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        TaskDetailView(taskId: "test-task-id")
    }
}
