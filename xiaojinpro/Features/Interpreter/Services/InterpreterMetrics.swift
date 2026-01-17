//
//  InterpreterMetrics.swift
//  xiaojinpro
//
//  Client-side metrics tracking for interpreter performance monitoring
//

import Foundation
import UIKit

// MARK: - Client Segment Metrics

/// Tracks timing metrics for a single audio segment
struct ClientSegmentMetrics {
    let segmentId: String
    let localIndex: Int

    // Client-side timestamps
    var audioReadyAt: Date?
    var encodingStartAt: Date?
    var encodingEndAt: Date?
    var apiSentAt: Date?
    var apiReceivedAt: Date?
    var sseReceivedAt: Date?

    // Metadata
    var audioSize: Int?
    var audioDuration: TimeInterval?
    var originalText: String?
    var translatedText: String?
    var isDuplicate: Bool = false

    // Backend timings (from SSE response)
    var backendTimings: BackendSegmentTimings?

    // MARK: - Computed Properties

    var encodingMs: Int? {
        guard let start = encodingStartAt, let end = encodingEndAt else { return nil }
        return Int(end.timeIntervalSince(start) * 1000)
    }

    var apiRttMs: Int? {
        guard let sent = apiSentAt, let received = apiReceivedAt else { return nil }
        return Int(received.timeIntervalSince(sent) * 1000)
    }

    var clientE2EMs: Int? {
        guard let sent = apiSentAt, let sseReceived = sseReceivedAt else { return nil }
        return Int(sseReceived.timeIntervalSince(sent) * 1000)
    }

    var totalE2EMs: Int? {
        guard let audioReady = audioReadyAt, let sseReceived = sseReceivedAt else { return nil }
        return Int(sseReceived.timeIntervalSince(audioReady) * 1000)
    }
}

// MARK: - Metrics Log Entry

struct MetricLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    enum LogLevel: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case debug = "DEBUG"
    }
}

// MARK: - Interpreter Metrics Service

@MainActor
class InterpreterMetrics: ObservableObject {
    static let shared = InterpreterMetrics()

    // MARK: - Published Properties

    @Published var logs: [MetricLog] = []
    @Published private(set) var segments: [String: ClientSegmentMetrics] = [:]

    // Session info
    private var sessionId: String?
    private var sessionStartedAt: Date?

    // MARK: - Lifecycle

    func startSession(sessionId: String) {
        self.sessionId = sessionId
        self.sessionStartedAt = Date()
        segments.removeAll()
        log(.info, "Session started: \(sessionId)")
    }

    func endSession() {
        if let sessionId = sessionId {
            log(.info, "Session ended: \(sessionId)")
        }
        sessionId = nil
    }

    // MARK: - Stage Tracking

    func audioReady(segmentId: String, localIndex: Int, audioSize: Int, duration: TimeInterval) {
        var metrics = ClientSegmentMetrics(segmentId: segmentId, localIndex: localIndex)
        metrics.audioReadyAt = Date()
        metrics.audioSize = audioSize
        metrics.audioDuration = duration
        segments[segmentId] = metrics

        log(.debug, "[\(localIndex)] Audio ready: \(audioSize) bytes, \(String(format: "%.1f", duration))s")
    }

    func encodingStart(segmentId: String) {
        segments[segmentId]?.encodingStartAt = Date()
    }

    func encodingEnd(segmentId: String) {
        segments[segmentId]?.encodingEndAt = Date()
        if let ms = segments[segmentId]?.encodingMs {
            log(.debug, "[\(segments[segmentId]?.localIndex ?? 0)] Encoding: \(ms)ms")
        }
    }

    func apiSent(segmentId: String) {
        segments[segmentId]?.apiSentAt = Date()
    }

    func apiReceived(segmentId: String) {
        segments[segmentId]?.apiReceivedAt = Date()
        if let ms = segments[segmentId]?.apiRttMs {
            log(.debug, "[\(segments[segmentId]?.localIndex ?? 0)] API RTT: \(ms)ms")
        }
    }

    /// Remap segment ID when backend returns a different ID than client-generated
    func remapSegmentId(from oldId: String, to newId: String) {
        guard oldId != newId, let segment = segments[oldId] else { return }
        segments[newId] = segment
        segments.removeValue(forKey: oldId)
    }

    func sseReceived(
        segmentId: String,
        backendTimings: BackendSegmentTimings?,
        originalText: String?,
        translatedText: String?,
        isDuplicate: Bool
    ) {
        segments[segmentId]?.sseReceivedAt = Date()
        segments[segmentId]?.backendTimings = backendTimings
        segments[segmentId]?.originalText = originalText
        segments[segmentId]?.translatedText = translatedText
        segments[segmentId]?.isDuplicate = isDuplicate

        if let metrics = segments[segmentId] {
            logSegmentComplete(metrics)
        }
    }

    // MARK: - Logging

    private func log(_ level: MetricLog.LogLevel, _ message: String) {
        let entry = MetricLog(timestamp: Date(), level: level, message: message)
        logs.append(entry)

        // Keep last 500 logs
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }

        #if DEBUG
        print("[InterpreterMetrics] \(level.rawValue): \(message)")
        #endif
    }

    private func logSegmentComplete(_ metrics: ClientSegmentMetrics) {
        var parts: [String] = []
        parts.append("[\(metrics.localIndex)]")

        if let e2e = metrics.clientE2EMs {
            parts.append("E2E: \(e2e)ms")
        }

        if let backend = metrics.backendTimings {
            parts.append("ASR: \(backend.asrMs ?? 0)ms")
            parts.append("Translate: \(backend.translateMs ?? 0)ms")
        }

        if metrics.isDuplicate {
            parts.append("(duplicate)")
        }

        log(.info, parts.joined(separator: " | "))
    }

    // MARK: - Export

    func exportLogs() -> String {
        var output = ""

        // Header
        output += "=== 同声传译性能日志 ===\n"
        output += "设备: \(UIDevice.current.model) | \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\n"
        if let sessionId = sessionId, let startTime = sessionStartedAt {
            let formatter = ISO8601DateFormatter()
            output += "会话: \(sessionId.prefix(8)) | \(formatter.string(from: startTime))\n"
        }
        output += "\n"

        // Segment details
        let sortedSegments = segments.values.sorted { $0.localIndex < $1.localIndex }
        for metrics in sortedSegments {
            output += "--- Segment \(metrics.localIndex) ---\n"

            // Client metrics
            output += "[客户端]\n"
            if let size = metrics.audioSize, let duration = metrics.audioDuration {
                output += "  音频: \(size / 1024)KB | \(String(format: "%.1f", duration))s\n"
            }
            if let encoding = metrics.encodingMs {
                output += "  编码: \(encoding)ms\n"
            }
            if let rtt = metrics.apiRttMs {
                output += "  API RTT: \(rtt)ms\n"
            }
            output += "\n"

            // Backend metrics
            if let backend = metrics.backendTimings {
                output += "[后端]\n"
                output += "  Session: \(backend.sessionFetchMs ?? 0)ms\n"
                output += "  ASR: \(backend.asrMs ?? 0)ms\n"
                output += "  R2: \(backend.r2UploadMs ?? 0)ms\n"
                output += "  去重: \(backend.dedupeMs ?? 0)ms\n"
                output += "  翻译: \(backend.translateMs ?? 0)ms\n"
                output += "  总计: \(backend.total)ms\n"
                output += "\n"
            }

            // E2E
            if let e2e = metrics.clientE2EMs {
                output += "[E2E]\n"
                output += "  客户端发送 → SSE 收到: \(e2e)ms\n"
                output += "\n"
            }

            // Content
            if metrics.isDuplicate {
                output += "状态: 重复段落\n"
            } else {
                if let text = metrics.originalText, !text.isEmpty {
                    output += "转录: \"\(text)\"\n"
                }
                if let translation = metrics.translatedText {
                    output += "翻译: \"\(translation)\"\n"
                }
            }
            output += "\n"
        }

        // Summary
        output += "--- 统计摘要 ---\n"
        let completed = sortedSegments.filter { $0.sseReceivedAt != nil }
        output += "总段数: \(completed.count)\n"

        if !completed.isEmpty {
            let avgEncoding = completed.compactMap { $0.encodingMs }.reduce(0, +) / max(1, completed.compactMap { $0.encodingMs }.count)
            let avgRtt = completed.compactMap { $0.apiRttMs }.reduce(0, +) / max(1, completed.compactMap { $0.apiRttMs }.count)
            let avgE2E = completed.compactMap { $0.clientE2EMs }.reduce(0, +) / max(1, completed.compactMap { $0.clientE2EMs }.count)

            output += "平均编码: \(avgEncoding)ms\n"
            output += "平均 API RTT: \(avgRtt)ms\n"
            output += "平均 E2E: \(avgE2E)ms\n"

            // Backend averages
            let backendMetrics = completed.compactMap { $0.backendTimings }
            if !backendMetrics.isEmpty {
                let avgAsr = backendMetrics.compactMap { $0.asrMs }.reduce(0, +) / backendMetrics.count
                let avgTranslate = backendMetrics.compactMap { $0.translateMs }.reduce(0, +) / backendMetrics.count
                let avgBackendTotal = backendMetrics.map { $0.total }.reduce(0, +) / backendMetrics.count

                output += "平均后端 ASR: \(avgAsr)ms\n"
                output += "平均后端翻译: \(avgTranslate)ms\n"
                output += "平均后端总计: \(avgBackendTotal)ms\n"
            }
        }

        return output
    }

    func copyToClipboard() {
        UIPasteboard.general.string = exportLogs()
    }

    func clear() {
        logs.removeAll()
        segments.removeAll()
        sessionId = nil
        sessionStartedAt = nil
    }

    // MARK: - Summary Stats

    var completedSegmentCount: Int {
        segments.values.filter { $0.sseReceivedAt != nil }.count
    }

    var averageE2EMs: Int? {
        let e2es = segments.values.compactMap { $0.clientE2EMs }
        guard !e2es.isEmpty else { return nil }
        return e2es.reduce(0, +) / e2es.count
    }

    var averageAsrMs: Int? {
        let asrs = segments.values.compactMap { $0.backendTimings?.asrMs }
        guard !asrs.isEmpty else { return nil }
        return asrs.reduce(0, +) / asrs.count
    }

    var averageTranslateMs: Int? {
        let translates = segments.values.compactMap { $0.backendTimings?.translateMs }
        guard !translates.isEmpty else { return nil }
        return translates.reduce(0, +) / translates.count
    }
}
