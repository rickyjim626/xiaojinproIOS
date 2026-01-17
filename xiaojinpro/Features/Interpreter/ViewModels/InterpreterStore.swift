//
//  InterpreterStore.swift
//  xiaojinpro
//
//  State management for real-time interpreter
//  Uses session-based backend API
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Interpreter Store

@MainActor
class InterpreterStore: ObservableObject {

    // MARK: - Published Properties

    @Published var currentSession: InterpreterSession?
    @Published var segments: [InterpreterSegment] = []
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var error: String?
    @Published var amplitude: Float = 0
    @Published var currentTime: TimeInterval = 0
    @Published var settings: InterpreterSettings = .default
    @Published var sessionStats: SessionStatsResponse?

    // MARK: - Services

    private let recorder = AudioRecorder()
    private let sessionService = InterpreterSessionService.shared
    private let metrics = InterpreterMetrics.shared

    // MARK: - Private Properties

    private var pendingSegments: [String: Int] = [:]  // segmentId -> segments array index

    // MARK: - Initialization

    init() {
        setupRecorder()
        setupSSEHandler()
        loadSettings()
    }

    // MARK: - Setup

    private func setupRecorder() {
        recorder.onSegmentReady = { [weak self] data, startTime, endTime, overlapDuration in
            Task { @MainActor in
                await self?.handleAudioSegment(
                    data: data,
                    startTime: startTime,
                    endTime: endTime,
                    overlapDuration: overlapDuration
                )
            }
        }
    }

    private func setupSSEHandler() {
        sessionService.onSSEEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleSSEEvent(event)
            }
        }
    }

    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "interpreter.settings"),
           let saved = try? JSONDecoder().decode(InterpreterSettings.self, from: data) {
            settings = saved
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "interpreter.settings")
        }
    }

    // MARK: - Recording Control

    func startRecording() async {
        guard !isRecording else { return }

        error = nil

        do {
            // 1. Create backend session (auto-detect source, target from settings)
            let config = SessionConfig.default(targetLanguage: settings.targetLanguage.rawValue)
            let response = try await sessionService.createSession(config: config)

            // 2. Start metrics session
            metrics.startSession(sessionId: response.sessionId)

            // 3. Start SSE stream
            await sessionService.startSSE()

            // 4. Create local session (source = auto-detect)
            currentSession = InterpreterSession(
                sourceLanguage: "auto",
                targetLanguage: settings.targetLanguage.fullCode
            )
            segments = []
            pendingSegments = [:]
            sessionStats = nil

            // 5. Start recording
            try await recorder.startRecording()
            isRecording = true
            isPaused = false

            // 6. Start amplitude observation
            startAmplitudeObservation()

            // 7. Haptic feedback
            if settings.hapticFeedback {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }

            print("[Interpreter] Started recording with session")

        } catch {
            self.error = error.localizedDescription
            isRecording = false
            sessionService.reset()
        }
    }

    func stopRecording() async {
        guard isRecording else { return }

        recorder.stopRecording()
        isRecording = false
        isPaused = false

        // Wait for pending segments to complete (max 15 seconds)
        let maxWait = 15
        var waited = 0
        while !pendingSegments.isEmpty && waited < maxWait {
            print("[Interpreter] Waiting for \(pendingSegments.count) pending segments...")
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
            waited += 1
        }

        // End backend session
        do {
            let response = try await sessionService.endSession()
            if let summary = response.summary {
                sessionStats = SessionStatsResponse(
                    totalAudioDuration: summary.totalDuration,
                    totalSegments: summary.totalSegments,
                    totalCharsTranscribed: 0,
                    totalCharsTranslated: 0
                )
                print("[Interpreter] Session ended: \(summary.totalSegments) segments")
            } else {
                print("[Interpreter] Session ended (no segments)")
            }
        } catch {
            print("[Interpreter] Failed to end session: \(error)")
        }

        // End metrics session and log summary
        metrics.endSession()
        print("[Interpreter] Metrics summary:\n\(metrics.exportLogs())")

        // Update local session and save to history
        if var session = currentSession {
            session.totalDuration = currentTime
            session.segments = segments
            currentSession = session

            // Save to history
            InterpreterHistoryManager.shared.save(session)
        }

        // Haptic feedback
        if settings.hapticFeedback {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func togglePause() {
        guard isRecording else { return }

        if isPaused {
            recorder.resumeRecording()
            isPaused = false
        } else {
            recorder.pauseRecording()
            isPaused = true
        }

        if settings.hapticFeedback {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    // MARK: - Audio Segment Processing

    private func handleAudioSegment(
        data: Data,
        startTime: TimeInterval,
        endTime: TimeInterval,
        overlapDuration: TimeInterval
    ) async {
        // Generate segment ID early for metrics tracking
        let segmentId = UUID().uuidString

        // Track: audio ready
        let audioDuration = endTime - startTime
        metrics.audioReady(segmentId: segmentId, localIndex: segments.count, audioSize: data.count, duration: audioDuration)

        // Create placeholder segment
        let segment = InterpreterSegment(
            startTime: startTime,
            endTime: endTime,
            status: .transcribing
        )
        let localIndex = segments.count
        segments.append(segment)

        do {
            // Track: encoding (for base64 conversion)
            metrics.encodingStart(segmentId: segmentId)

            // Track: API sent
            metrics.apiSent(segmentId: segmentId)

            // Send to backend (async - result via SSE)
            let response = try await sessionService.processAudio(
                audioData: data,
                format: AACEncoder.audioFormat,  // "aac" on device, "wav" on simulator
                startTime: startTime,
                endTime: endTime,
                isFinal: false
            )

            // Track: encoding end (base64 happens inside processAudio)
            metrics.encodingEnd(segmentId: response.segmentId)

            // Track: API received (202 Accepted)
            metrics.apiReceived(segmentId: response.segmentId)

            // Map backend segment ID to local index (use segmentId, not segmentIndex!)
            pendingSegments[response.segmentId] = localIndex

            // Update metrics mapping if segmentId changed
            if response.segmentId != segmentId {
                metrics.segments[response.segmentId] = metrics.segments[segmentId]
                metrics.segments.removeValue(forKey: segmentId)
            }

            print("[Interpreter] Segment \(response.segmentId) submitted, local index: \(localIndex)")

        } catch {
            // Mark as failed
            segments[localIndex].status = .failed
            segments[localIndex].originalText = error.localizedDescription
            print("[Interpreter] Failed to submit segment: \(error)")
        }
    }

    // MARK: - SSE Event Handling

    private func handleSSEEvent(_ event: InterpreterSSEEvent) {
        switch event {
        case .ready(let sessionId):
            print("[Interpreter] SSE ready: \(sessionId)")

        case .segment(let segmentEvent):
            handleSegmentEvent(segmentEvent)

        case .error(let message):
            print("[Interpreter] SSE error: \(message)")
            self.error = message

        case .heartbeat:
            // Keep alive
            break

        case .ended(let summary):
            print("[Interpreter] Session ended via SSE: \(summary.totalSegments) segments")
            sessionStats = SessionStatsResponse(
                totalAudioDuration: summary.totalDuration,
                totalSegments: summary.totalSegments,
                totalCharsTranscribed: 0,
                totalCharsTranslated: 0
            )

        case .unknown(let eventType, let data):
            print("[Interpreter] Unknown SSE event: \(eventType), data: \(data)")
        }
    }

    private func handleSegmentEvent(_ event: SegmentEvent) {
        // Track: SSE received with backend timings
        metrics.sseReceived(
            segmentId: event.segmentId,
            backendTimings: event.timings,
            originalText: event.deduplicated,
            translatedText: event.translated,
            isDuplicate: event.isDuplicate
        )

        // Find local segment index using segmentId
        guard let localIndex = pendingSegments[event.segmentId] else {
            print("[Interpreter] Received segment \(event.segmentId) but no local mapping")
            return
        }

        guard localIndex < segments.count else {
            print("[Interpreter] Local index \(localIndex) out of bounds")
            return
        }

        // Update segment with results
        if event.isDuplicate {
            segments[localIndex].originalText = "(重复)"
            segments[localIndex].status = .completed
        } else {
            segments[localIndex].originalText = event.deduplicated
            segments[localIndex].translatedText = event.translated
            segments[localIndex].status = .completed
        }

        // Remove from pending
        pendingSegments.removeValue(forKey: event.segmentId)

        // Haptic feedback
        if settings.hapticFeedback {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }

        // Log timing info
        if let timings = event.timings {
            print("[Interpreter] Segment completed: ASR=\(timings.asrMs ?? 0)ms, Translate=\(timings.translateMs ?? 0)ms, Total=\(event.latencyMs ?? 0)ms")
        } else {
            print("[Interpreter] Segment completed: \(event.deduplicated.prefix(50))...")
        }
    }

    // MARK: - Amplitude Observation

    private func startAmplitudeObservation() {
        Task {
            while isRecording {
                amplitude = recorder.amplitude
                currentTime = recorder.currentTime

                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
    }

    // MARK: - Settings

    func updateTargetLanguage(_ language: TargetLanguage) {
        settings.targetLanguage = language
        saveSettings()
    }

    func toggleAutoScroll() {
        settings.autoScroll.toggle()
        saveSettings()
    }

    func toggleShowConfidence() {
        settings.showConfidence.toggle()
        saveSettings()
    }

    func toggleHapticFeedback() {
        settings.hapticFeedback.toggle()
        saveSettings()
    }

    // MARK: - Session Management

    func clearSession() {
        segments.removeAll()
        currentSession = nil
        error = nil
        currentTime = 0
        pendingSegments = [:]
        sessionStats = nil
    }

    func exportSession() -> String? {
        guard !segments.isEmpty else { return nil }

        var output = ""
        for segment in segments where segment.status == .completed {
            output += "[\(formatTime(segment.startTime))] \(segment.originalText)\n"
            if let translation = segment.translatedText {
                output += "  → \(translation)\n"
            }
            output += "\n"
        }

        return output.isEmpty ? nil : output
    }

    func shareSession() {
        guard let text = exportSession() else { return }

        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    func exportMetrics() -> String {
        metrics.exportLogs()
    }

    func copyMetricsToClipboard() {
        metrics.copyToClipboard()
    }

    func shareMetrics() {
        let text = metrics.exportLogs()

        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Preview Helper

#if DEBUG
extension InterpreterStore {
    static var preview: InterpreterStore {
        let store = InterpreterStore()
        store.segments = [
            InterpreterSegment(
                originalText: "Hello, how are you doing today?",
                translatedText: "你好，你今天怎么样？",
                startTime: 0,
                endTime: 4,
                status: .completed,
                confidence: 0.95
            ),
            InterpreterSegment(
                originalText: "The weather is really nice.",
                translatedText: "天气真的很好。",
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
            )
        ]
        store.isRecording = true
        store.amplitude = 0.6
        store.currentTime = 12.5
        return store
    }
}
#endif
