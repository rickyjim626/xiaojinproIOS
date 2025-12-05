//
//  SkillsView.swift
//  xiaojinpro
//
//  Created by Claude on 2025/12/5.
//

import SwiftUI

struct SkillsView: View {
    @StateObject private var service = SkillService.shared
    @StateObject private var storage = LocalStorage.shared
    @State private var searchText = ""
    @State private var selectedSkill: Skill?
    @State private var selectedCategory: SkillCategory?
    @State private var showingRecentTasks = false

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.skills.isEmpty {
                    LoadingView()
                } else if service.skills.isEmpty {
                    EmptyStateView(
                        icon: "wand.and.stars",
                        title: "暂无可用能力",
                        message: "请检查网络连接或联系管理员",
                        action: { Task { await service.fetchSkills() } },
                        actionTitle: "重试"
                    )
                } else {
                    skillsContent
                }
            }
            .navigationTitle("能力中心")
            .searchable(text: $searchText, prompt: "搜索能力")
            .refreshable {
                await service.fetchSkills()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingRecentTasks = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(item: $selectedSkill) { skill in
                SkillExecutionSheet(skill: skill)
            }
            .sheet(isPresented: $showingRecentTasks) {
                RecentTasksSheet()
            }
        }
        .task {
            if storage.isCacheStale() {
                await service.fetchSkills()
            } else if let cached = storage.getCachedSkills(), !cached.isEmpty {
                // Use cache
            } else {
                await service.fetchSkills()
            }
        }
        .onChange(of: service.skills) { _, newSkills in
            if !newSkills.isEmpty {
                storage.cacheSkills(newSkills)
            }
        }
    }

    private var skillsContent: some View {
        VStack(spacing: 0) {
            // Category filter
            categoryFilterBar

            // Skills list
            skillsList
        }
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryFilterChip(
                    title: "全部",
                    icon: "square.grid.2x2",
                    isSelected: selectedCategory == nil,
                    color: .gray
                ) {
                    withAnimation { selectedCategory = nil }
                }

                ForEach(service.categories, id: \.self) { category in
                    CategoryFilterChip(
                        title: category.displayName,
                        icon: category.icon,
                        isSelected: selectedCategory == category,
                        color: categoryColor(category)
                    ) {
                        withAnimation {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private var skillsList: some View {
        List {
            if let category = selectedCategory {
                // Single category view
                ForEach(filteredSkills(for: category)) { skill in
                    SkillRow(skill: skill)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSkill = skill
                        }
                }
            } else {
                // All categories view
                ForEach(service.categories, id: \.self) { category in
                    let skills = filteredSkills(for: category)
                    if !skills.isEmpty {
                        Section(header: categoryHeader(category)) {
                            ForEach(skills) { skill in
                                SkillRow(skill: skill)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedSkill = skill
                                    }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func categoryHeader(_ category: SkillCategory) -> some View {
        HStack {
            Image(systemName: category.icon)
                .foregroundColor(categoryColor(category))
            Text(category.displayName)
                .fontWeight(.semibold)
            Spacer()
            Text("\(service.skills(for: category).count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func filteredSkills(for category: SkillCategory) -> [Skill] {
        let categorySkills = service.skills(for: category)

        if searchText.isEmpty {
            return categorySkills
        }

        return categorySkills.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func categoryColor(_ category: SkillCategory) -> Color {
        switch category {
        case .devops: return .blue
        case .videoEdit: return .purple
        case .timeline: return .orange
        case .admin: return .red
        case .general: return .green
        }
    }
}

// MARK: - Category Filter Chip
struct CategoryFilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.2) : Color(.systemGray6))
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

// MARK: - Skill Row
struct SkillRow: View {
    let skill: Skill

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: skill.category.icon)
                    .foregroundColor(categoryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(skill.displayName)
                        .font(.headline)

                    if skill.requiresConfirmation {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.orange)
                            .font(.caption2)
                    }
                }

                Text(skill.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                // Permission badges
                if !skill.permissions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(skill.permissions.prefix(2), id: \.self) { permission in
                            Text(formatPermission(permission))
                                .font(.system(size: 9))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)
                        }
                        if skill.permissions.count > 2 {
                            Text("+\(skill.permissions.count - 2)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var categoryColor: Color {
        switch skill.category {
        case .devops: return .blue
        case .videoEdit: return .purple
        case .timeline: return .orange
        case .admin: return .red
        case .general: return .green
        }
    }

    private func formatPermission(_ permission: String) -> String {
        permission.split(separator: ":").last.map(String.init) ?? permission
    }
}

// MARK: - Skill Execution Sheet
struct SkillExecutionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let skill: Skill
    @StateObject private var executor: SkillExecutor
    @State private var showingConfirmation = false

    init(skill: Skill) {
        self.skill = skill
        _executor = StateObject(wrappedValue: SkillExecutor(skill: skill))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header card
                    skillHeaderCard

                    // Parameters form
                    if let properties = skill.parameters.properties, !properties.isEmpty {
                        parametersSection(properties: properties)
                    }

                    // Confirmation warning
                    if skill.requiresConfirmation {
                        confirmationWarning
                    }

                    // Task status
                    if let task = executor.task {
                        taskStatusSection(task: task)
                    }

                    // Error
                    if let error = executor.error {
                        errorSection(error: error)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(skill.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    executeButton
                }
            }
            .alert("确认执行", isPresented: $showingConfirmation) {
                Button("取消", role: .cancel) {}
                Button("确认执行", role: .destructive) {
                    executor.executeWithStream()
                }
            } message: {
                Text("此操作可能会对系统产生影响，确定要执行吗？")
            }
        }
    }

    private var skillHeaderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(categoryColor.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Image(systemName: skill.category.icon)
                        .font(.title2)
                        .foregroundColor(categoryColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.category.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(skill.name)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Text(skill.description)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Permissions
            if !skill.permissions.isEmpty {
                Divider()
                HStack {
                    Text("权限要求:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(skill.permissions, id: \.self) { permission in
                        Text(permission)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func parametersSection(properties: [String: SkillParameterSchema.PropertySchema]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("参数配置")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                ForEach(Array(properties.keys.sorted()), id: \.self) { key in
                    if let schema = properties[key] {
                        EnhancedParameterField(
                            key: key,
                            schema: schema,
                            isRequired: skill.parameters.required?.contains(key) ?? false,
                            value: Binding(
                                get: { executor.arguments[key] },
                                set: { executor.setArgument(key, value: $0) }
                            )
                        )
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }

    private var confirmationWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("需要确认")
                    .font(.headline)
                Text("此操作可能会对系统产生影响，请确保参数正确后再执行")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private func taskStatusSection(task: XJPTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("执行状态")
                .font(.headline)
                .padding(.horizontal, 4)

            EnhancedTaskStatusView(task: task)
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
        }
    }

    private func errorSection(error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)

            Text(error)
                .font(.caption)
                .foregroundColor(.red)

            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var executeButton: some View {
        if executor.isExecuting {
            Button("取消") {
                executor.cancel()
            }
            .foregroundColor(.red)
        } else if executor.task?.status == .succeeded {
            Button("完成") {
                dismiss()
            }
        } else {
            Button("执行") {
                if skill.requiresConfirmation {
                    showingConfirmation = true
                } else {
                    executor.executeWithStream()
                }
            }
            .disabled(executor.isExecuting || !executor.validateArguments().isEmpty)
        }
    }

    private var categoryColor: Color {
        switch skill.category {
        case .devops: return .blue
        case .videoEdit: return .purple
        case .timeline: return .orange
        case .admin: return .red
        case .general: return .green
        }
    }
}

// MARK: - Enhanced Parameter Field
struct EnhancedParameterField: View {
    let key: String
    let schema: SkillParameterSchema.PropertySchema
    let isRequired: Bool
    @Binding var value: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label
            HStack {
                Text(schema.description ?? key)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if isRequired {
                    Text("*")
                        .foregroundColor(.red)
                }
                Spacer()
                if let defaultValue = schema.defaultValue?.value {
                    Text("默认: \(String(describing: defaultValue))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Input based on type
            inputField

            // Validation hints
            if let min = schema.minimum, let max = schema.maximum {
                Text("范围: \(Int(min)) - \(Int(max))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var inputField: some View {
        switch schema.type {
        case "string":
            if let enumValues = schema.enumValues {
                // Enum picker
                Menu {
                    Button("清除选择") {
                        value = nil
                    }
                    ForEach(enumValues, id: \.self) { option in
                        Button(option) {
                            value = option
                        }
                    }
                } label: {
                    HStack {
                        Text(value as? String ?? "请选择...")
                            .foregroundColor(value == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            } else if schema.format == "uri" {
                // URL field
                TextField("https://...", text: stringBinding)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
            } else {
                // Regular text field
                TextField(key, text: stringBinding)
                    .textFieldStyle(.roundedBorder)
            }

        case "integer":
            HStack {
                TextField(key, text: numberStringBinding)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)

                if let min = schema.minimum, let max = schema.maximum {
                    Stepper("", value: intBinding, in: Int(min)...Int(max))
                        .labelsHidden()
                }
            }

        case "number":
            TextField(key, text: numberStringBinding)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)

        case "boolean":
            Toggle(isOn: boolBinding) {
                Text(value as? Bool == true ? "是" : "否")
                    .foregroundColor(.secondary)
            }
            .toggleStyle(.switch)

        case "array":
            // Array input (simplified as comma-separated)
            TextField("逗号分隔的值", text: arrayStringBinding)
                .textFieldStyle(.roundedBorder)

        default:
            TextField(key, text: stringBinding)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { value as? String ?? "" },
            set: { value = $0.isEmpty ? nil : $0 }
        )
    }

    private var numberStringBinding: Binding<String> {
        Binding(
            get: {
                if let num = value as? Int {
                    return String(num)
                } else if let num = value as? Double {
                    return String(num)
                }
                return ""
            },
            set: {
                if $0.isEmpty {
                    value = nil
                } else if schema.type == "integer" {
                    value = Int($0)
                } else {
                    value = Double($0)
                }
            }
        )
    }

    private var intBinding: Binding<Int> {
        Binding(
            get: { value as? Int ?? Int(schema.minimum ?? 0) },
            set: { value = $0 }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { value as? Bool ?? false },
            set: { value = $0 }
        )
    }

    private var arrayStringBinding: Binding<String> {
        Binding(
            get: {
                if let arr = value as? [String] {
                    return arr.joined(separator: ", ")
                }
                return ""
            },
            set: {
                if $0.isEmpty {
                    value = nil
                } else {
                    value = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                }
            }
        )
    }
}

// MARK: - Enhanced Task Status View
struct EnhancedTaskStatusView: View {
    let task: XJPTask
    @State private var showingResult = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            HStack {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 40, height: 40)

                    if task.status == .running {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: task.status.icon)
                            .foregroundColor(statusColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.status.displayName)
                        .font(.headline)
                    Text("任务 ID: \(task.id.prefix(8))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let duration = task.formattedDuration {
                    VStack(alignment: .trailing) {
                        Text(duration)
                            .font(.headline)
                            .fontDesign(.monospaced)
                        Text("耗时")
                            .font(.caption2)
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
                        Text("\(progress)%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                }
            }

            // Error message
            if let error = task.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            // Result
            if task.status == .succeeded, let result = task.result {
                Divider()
                Button {
                    showingResult = true
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("查看执行结果")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .sheet(isPresented: $showingResult) {
                    TaskResultSheet(result: result)
                }
            }
        }
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

// MARK: - Task Result Sheet
struct TaskResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    let result: AnyCodable

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("执行结果")
                        .font(.headline)

                    Text(formatResult())
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                    Button {
                        UIPasteboard.general.string = formatResult()
                    } label: {
                        Label("复制结果", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("执行结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatResult() -> String {
        if let dict = result.value as? [String: Any] {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        return String(describing: result.value)
    }
}

// MARK: - Recent Tasks Sheet
struct RecentTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var taskService = TaskService.shared

    var body: some View {
        NavigationStack {
            Group {
                if taskService.isLoading && taskService.tasks.isEmpty {
                    LoadingView()
                } else if taskService.tasks.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "暂无任务记录",
                        message: "执行技能后会在这里显示",
                        action: nil,
                        actionTitle: nil
                    )
                } else {
                    tasksList
                }
            }
            .navigationTitle("最近任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await taskService.fetchTasks()
        }
    }

    private var tasksList: some View {
        List {
            ForEach(taskService.tasks) { task in
                RecentTaskRow(task: task)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await taskService.fetchTasks()
        }
    }
}

// MARK: - Recent Task Row
struct RecentTaskRow: View {
    let task: XJPTask

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.skillName)
                    .font(.headline)

                HStack {
                    Text(task.createdAt.relativeString)
                    if let duration = task.formattedDuration {
                        Text("(\(duration))")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Text(task.status.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.2))
                .foregroundColor(statusColor)
                .cornerRadius(4)
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

#Preview {
    SkillsView()
}
