//
//  InterpreterView.swift
//  xiaojinpro
//
//  Real-time interpreter main interface
//  Split view: original text (top) + translated text (bottom)
//

import SwiftUI

// MARK: - Interpreter View

struct InterpreterView: View {
    @StateObject private var store = InterpreterStore()
    @State private var showSettings = false
    @State private var showMenu = false
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Split content area
                if store.segments.isEmpty && !store.isRecording {
                    TranscriptEmptyView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    splitContentView
                }

                Divider()

                // Bottom control area
                bottomControlArea
            }
            .navigationTitle("同声传译")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Left: Menu
                ToolbarItem(placement: .topBarLeading) {
                    menuButton
                }

                // Right: Timer + Settings
                ToolbarItemGroup(placement: .topBarTrailing) {
                    timerView
                    settingsButton
                }
            }
            .sheet(isPresented: $showSettings) {
                InterpreterSettingsView(store: store)
            }
            .sheet(isPresented: $showHistory) {
                InterpreterHistoryView()
            }
            .alert("错误", isPresented: .constant(store.error != nil)) {
                Button("确定") {
                    store.error = nil
                }
            } message: {
                if let error = store.error {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Split Content View

    private var splitContentView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Original text panel (top)
                TranscriptPanelView(
                    mode: .original,
                    segments: store.segments,
                    targetLanguage: store.settings.targetLanguage,
                    autoScroll: store.settings.autoScroll,
                    showConfidence: store.settings.showConfidence
                )
                .frame(height: geometry.size.height * 0.5)

                Divider()

                // Translated text panel (bottom)
                TranscriptPanelView(
                    mode: .translated,
                    segments: store.segments,
                    targetLanguage: store.settings.targetLanguage,
                    autoScroll: store.settings.autoScroll,
                    showConfidence: false
                )
                .frame(height: geometry.size.height * 0.5)
            }
        }
    }

    // MARK: - Menu Button

    private var menuButton: some View {
        Menu {
            // History
            Button {
                showHistory = true
            } label: {
                Label("历史记录", systemImage: "clock.arrow.circlepath")
            }
            .disabled(store.isRecording)

            // Share
            Button {
                store.shareSession()
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            .disabled(store.segments.isEmpty)

            Divider()

            // Clear
            Button(role: .destructive) {
                store.clearSession()
            } label: {
                Label("清除当前会话", systemImage: "trash")
            }
            .disabled(store.segments.isEmpty || store.isRecording)

        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.body)
        }
    }

    // MARK: - Timer View

    private var timerView: some View {
        HStack(spacing: 4) {
            if store.isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            }
            Text(formatTime(store.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(store.isRecording ? .red : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }

    // MARK: - Settings Button

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gear")
        }
    }

    // MARK: - Bottom Control Area

    private var bottomControlArea: some View {
        VStack(spacing: 12) {
            // Waveform
            AudioWaveformView(
                amplitude: store.amplitude,
                isRecording: store.isRecording
            )
            .frame(height: 40)
            .padding(.horizontal)

            // Record button
            recordButton
                .padding(.bottom, 16)
        }
        .padding(.top, 12)
        .background(Color(.systemBackground))
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            Task {
                await store.toggleRecording()
            }
        } label: {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        store.isRecording ? Color.red : Color.blue,
                        lineWidth: 4
                    )
                    .frame(width: 64, height: 64)

                // Inner fill
                Circle()
                    .fill(store.isRecording ? Color.red : Color.blue)
                    .frame(width: 52, height: 52)

                // Icon
                if store.isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .scaleEffect(store.isRecording ? 1.1 : 1.0)
        .animation(.spring(response: 0.3), value: store.isRecording)
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}

// MARK: - Interpreter Settings View

struct InterpreterSettingsView: View {
    @ObservedObject var store: InterpreterStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("目标语言") {
                    Picker("翻译成", selection: Binding(
                        get: { store.settings.targetLanguage },
                        set: { store.updateTargetLanguage($0) }
                    )) {
                        ForEach(TargetLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("显示") {
                    Toggle("自动滚动到最新", isOn: Binding(
                        get: { store.settings.autoScroll },
                        set: { _ in store.toggleAutoScroll() }
                    ))

                    Toggle("显示识别置信度", isOn: Binding(
                        get: { store.settings.showConfidence },
                        set: { _ in store.toggleShowConfidence() }
                    ))
                }

                Section("反馈") {
                    Toggle("触觉反馈", isOn: Binding(
                        get: { store.settings.hapticFeedback },
                        set: { _ in store.toggleHapticFeedback() }
                    ))
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - History View

struct InterpreterHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var historyManager = InterpreterHistoryManager.shared
    @State private var selectedSession: InterpreterSession?

    var body: some View {
        NavigationStack {
            Group {
                if historyManager.sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("暂无历史记录")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("完成的同声传译会话将显示在这里")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    List {
                        ForEach(historyManager.sessions) { session in
                            SessionRowView(session: session)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedSession = session
                                }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                historyManager.delete(historyManager.sessions[index])
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                if !historyManager.sessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("清空", role: .destructive) {
                            historyManager.clearAll()
                        }
                    }
                }
            }
            .sheet(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
        }
    }
}

// MARK: - Session Row

private struct SessionRowView: View {
    let session: InterpreterSession

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dateFormatter.string(from: session.createdAt))
                    .font(.headline)
                Spacer()
                Text(formatDuration(session.totalDuration))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("\(session.segments.count) 段", systemImage: "text.bubble")
                Spacer()
                Text("\(session.sourceLanguage) → \(session.targetLanguage)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let firstSegment = session.segments.first(where: { !$0.originalText.isEmpty }) {
                Text(firstSegment.originalText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Session Detail View

private struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let session: InterpreterSession

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.segments.filter { !$0.originalText.isEmpty }) { segment in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(formatTime(segment.startTime))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        Text(segment.originalText)
                            .font(.body)

                        if let translation = segment.translatedText {
                            Text(translation)
                                .font(.body)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("会话详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: exportText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var exportText: String {
        var output = "同声传译记录\n"
        output += "时间: \(session.createdAt)\n"
        output += "时长: \(Int(session.totalDuration))秒\n\n"

        for segment in session.segments where !segment.originalText.isEmpty {
            output += "[\(formatTime(segment.startTime))] \(segment.originalText)\n"
            if let translation = segment.translatedText {
                output += "  → \(translation)\n"
            }
            output += "\n"
        }

        return output
    }
}

// MARK: - Preview

#Preview {
    InterpreterView()
}

#Preview("Settings") {
    InterpreterSettingsView(store: InterpreterStore.preview)
}

#Preview("History") {
    InterpreterHistoryView()
}
