//
//  TranscriptListView.swift
//  xiaojinpro
//
//  Transcript display components for split view layout
//

import SwiftUI

// MARK: - Display Mode

enum TranscriptDisplayMode {
    case original    // 原文 (ASR)
    case translated  // 译文
}

// MARK: - Transcript Panel View

struct TranscriptPanelView: View {
    let mode: TranscriptDisplayMode
    let segments: [InterpreterSegment]
    let targetLanguage: TargetLanguage
    let autoScroll: Bool
    let showConfidence: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            panelHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))

            // Content
            if segments.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                transcriptScrollView
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: mode == .original ? "waveform" : "text.bubble")
                .font(.caption)
                .foregroundColor(mode == .original ? .blue : .green)

            Text(headerTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Spacer()

            if mode == .original {
                Text("自动检测")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
            } else {
                Text(targetLanguage.label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
            }
        }
    }

    private var headerTitle: String {
        mode == .original ? "原文" : "译文"
    }

    // MARK: - Scroll View

    private var transcriptScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(segments) { segment in
                        TranscriptTextRow(
                            segment: segment,
                            mode: mode,
                            showConfidence: showConfidence
                        )
                        .id("\(mode)-\(segment.id)")
                    }
                }
                .padding()
            }
            .onChange(of: segments.count) { _, _ in
                if autoScroll, let lastSegment = segments.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("\(mode)-\(lastSegment.id)", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: mode == .original ? "waveform.slash" : "text.bubble")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))

            Text(mode == .original ? "等待录音..." : "等待翻译...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Transcript Text Row

struct TranscriptTextRow: View {
    let segment: InterpreterSegment
    let mode: TranscriptDisplayMode
    let showConfidence: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Time indicator
            Text(formatTime(segment.startTime))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .leading)

            // Content
            contentView
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch mode {
        case .original:
            originalContentView
        case .translated:
            translatedContentView
        }
    }

    @ViewBuilder
    private var originalContentView: some View {
        if segment.originalText.isEmpty {
            if segment.status == .transcribing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("识别中...")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("...")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(segment.originalText)
                    .font(.body)
                    .foregroundColor(.primary)

                if showConfidence, let confidence = segment.confidence {
                    Text("\(Int(confidence * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var translatedContentView: some View {
        if let translation = segment.translatedText, !translation.isEmpty {
            Text(translation)
                .font(.body)
                .foregroundColor(.primary)
        } else if segment.status == .translating || segment.status == .transcribing {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.6)
                Text(segment.status == .transcribing ? "等待原文..." : "翻译中...")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        } else if segment.status == .completed && segment.translatedText == nil {
            Text("(无翻译)")
                .font(.body)
                .foregroundColor(.secondary)
        } else {
            Text("...")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Empty State View (for initial state)

struct TranscriptEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("准备就绪")
                .font(.headline)
                .foregroundColor(.primary)

            Text("点击录音按钮开始\n实时语音转文字和翻译")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Legacy Support (for backward compatibility)

struct TranscriptListView: View {
    let segments: [InterpreterSegment]
    let showConfidence: Bool
    let autoScroll: Bool

    var body: some View {
        TranscriptPanelView(
            mode: .original,
            segments: segments,
            targetLanguage: .chinese,
            autoScroll: autoScroll,
            showConfidence: showConfidence
        )
    }
}

// MARK: - Preview

#Preview("Split View") {
    VStack(spacing: 0) {
        TranscriptPanelView(
            mode: .original,
            segments: previewSegments,
            targetLanguage: .chinese,
            autoScroll: true,
            showConfidence: false
        )

        Divider()

        TranscriptPanelView(
            mode: .translated,
            segments: previewSegments,
            targetLanguage: .chinese,
            autoScroll: true,
            showConfidence: false
        )
    }
}

#Preview("Empty State") {
    TranscriptEmptyView()
}

private let previewSegments = [
    InterpreterSegment(
        originalText: "Hello, how are you doing today?",
        translatedText: "你好，你今天怎么样？",
        startTime: 0,
        endTime: 4,
        status: .completed,
        confidence: 0.95
    ),
    InterpreterSegment(
        originalText: "The weather is really nice outside.",
        translatedText: "外面的天气真的很好。",
        startTime: 4,
        endTime: 8,
        status: .completed,
        confidence: 0.92
    ),
    InterpreterSegment(
        originalText: "I'm doing great, thank you!",
        translatedText: nil,
        startTime: 8,
        endTime: 12,
        status: .translating
    ),
    InterpreterSegment(
        originalText: "",
        translatedText: nil,
        startTime: 12,
        endTime: 16,
        status: .transcribing
    )
]
