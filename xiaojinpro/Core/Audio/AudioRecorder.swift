//
//  AudioRecorder.swift
//  xiaojinpro
//
//  AVAudioEngine based recorder with segment buffering
//

import AVFoundation
import Foundation

// MARK: - Audio Recorder Delegate
protocol AudioRecorderDelegate: AnyObject {
    func audioRecorder(_ recorder: AudioRecorder, didCaptureSegment data: Data, startTime: TimeInterval, endTime: TimeInterval)
    func audioRecorder(_ recorder: AudioRecorder, didUpdateAmplitude amplitude: Float)
    func audioRecorder(_ recorder: AudioRecorder, didFailWithError error: Error)
}

// MARK: - Audio Recorder
@MainActor
class AudioRecorder: ObservableObject {

    // MARK: - Published Properties

    @Published var isRecording = false
    @Published var amplitude: Float = 0
    @Published var currentTime: TimeInterval = 0
    @Published var error: String?

    // MARK: - Delegate

    weak var delegate: AudioRecorderDelegate?

    // MARK: - Callback (alternative to delegate)

    /// Callback when audio segment is ready
    /// Parameters: (aacData, startTime, endTime, overlapDuration)
    var onSegmentReady: ((Data, TimeInterval, TimeInterval, TimeInterval) -> Void)?

    // MARK: - Configuration

    let sampleRate: Double = 16000
    let segmentDuration: TimeInterval = 10.0  // 10-second segments
    let overlapDuration: TimeInterval = 2.0   // 2-second overlap between segments

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioConverter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    private var pcmBuffer: [Float] = []
    private var overlapBuffer: [Float] = []  // Stores last 2 seconds for overlap
    private var segmentStartTime: TimeInterval = 0
    private var recordingStartTime: Date?

    private let bufferSize: AVAudioFrameCount = 1024
    private var isConfigured = false

    // MARK: - Initialization

    init() {}

    deinit {
        // Cleanup audio engine directly (can't call MainActor method from deinit)
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
    }

    // MARK: - Public Methods

    func startRecording() async throws {
        guard !isRecording else { return }

        // Request microphone permission
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            throw AudioRecorderError.permissionDenied
        }

        // Configure audio session
        try configureAudioSession()

        // Setup audio engine
        try setupAudioEngine()

        // Start recording
        try audioEngine?.start()

        isRecording = true
        recordingStartTime = Date()
        segmentStartTime = 0
        pcmBuffer.removeAll()
        overlapBuffer.removeAll()
        error = nil

        print("Audio recording started")
    }

    func stopRecording() {
        guard isRecording else { return }

        // Process any remaining audio
        if !pcmBuffer.isEmpty {
            processCurrentSegment(isFinal: true)
        }

        // Stop and cleanup
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        audioConverter = nil
        targetFormat = nil

        isRecording = false
        amplitude = 0
        currentTime = 0
        isConfigured = false

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)

        print("[AudioRecorder] Recording stopped")
    }

    func pauseRecording() {
        audioEngine?.pause()
    }

    func resumeRecording() {
        try? audioEngine?.start()
    }

    // MARK: - Private Methods

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(Double(bufferSize) / sampleRate)
        try session.setActive(true)
    }

    private func setupAudioEngine() throws {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw AudioRecorderError.engineCreationFailed
        }

        inputNode = engine.inputNode
        guard let input = inputNode else {
            throw AudioRecorderError.inputNodeUnavailable
        }

        // Input format (hardware format) - use this for the tap
        let inputFormat = input.inputFormat(forBus: 0)
        print("[AudioRecorder] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Target format (16kHz mono) - for conversion
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.formatCreationFailed
        }
        self.targetFormat = target

        // Create audio converter for sample rate conversion
        guard let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw AudioRecorderError.formatCreationFailed
        }
        self.audioConverter = converter

        // Install tap with native input format (NOT target format)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            Task { @MainActor in
                self?.processAudioBuffer(buffer, time: time)
            }
        }

        engine.prepare()
        isConfigured = true
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let converter = audioConverter,
              let targetFmt = targetFormat else { return }

        // Update current time
        if let startTime = recordingStartTime {
            currentTime = Date().timeIntervalSince(startTime)
        }

        // Update amplitude for visualization (use original buffer)
        if let channelData = buffer.floatChannelData?[0] {
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameCount {
                sum += abs(channelData[i])
            }
            let avgAmplitude = sum / Float(frameCount)
            amplitude = min(1.0, avgAmplitude * 10)
        }

        // Convert to target format (16kHz mono)
        let ratio = sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFmt,
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("[AudioRecorder] Conversion error: \(error)")
            return
        }

        // Get converted samples
        guard let convertedChannelData = convertedBuffer.floatChannelData?[0] else { return }
        let convertedFrameCount = Int(convertedBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: convertedChannelData, count: convertedFrameCount))
        pcmBuffer.append(contentsOf: samples)

        // Check if segment is complete
        let samplesPerSegment = Int(sampleRate * segmentDuration)
        if pcmBuffer.count >= samplesPerSegment {
            processCurrentSegment(isFinal: false)
        }
    }

    private func processCurrentSegment(isFinal: Bool) {
        guard !pcmBuffer.isEmpty else { return }

        let samplesPerSegment = Int(sampleRate * segmentDuration)
        let overlapSamples = Int(sampleRate * overlapDuration)
        let samplesToProcess = isFinal ? pcmBuffer.count : min(pcmBuffer.count, samplesPerSegment)

        // Build segment: overlap from previous + current samples
        var segmentSamples: [Float] = []
        let actualOverlapDuration: TimeInterval

        if !overlapBuffer.isEmpty {
            segmentSamples.append(contentsOf: overlapBuffer)
            actualOverlapDuration = Double(overlapBuffer.count) / sampleRate
        } else {
            actualOverlapDuration = 0
        }

        // Add current samples
        segmentSamples.append(contentsOf: pcmBuffer.prefix(samplesToProcess))

        // Save last 2 seconds for next segment's overlap (unless final)
        if !isFinal {
            let currentSamples = Array(pcmBuffer.prefix(samplesToProcess))
            overlapBuffer = Array(currentSamples.suffix(min(overlapSamples, currentSamples.count)))
        } else {
            overlapBuffer.removeAll()
        }

        pcmBuffer.removeFirst(samplesToProcess)

        // Calculate time range (effective start includes overlap)
        let effectiveStartTime = max(0, segmentStartTime - actualOverlapDuration)
        let endTime = segmentStartTime + (Double(samplesToProcess) / sampleRate)

        // Encode to AAC
        Task {
            do {
                let aacData = try await AACEncoder.encode(
                    samples: segmentSamples,
                    sampleRate: sampleRate
                )

                // Notify delegate or callback
                await MainActor.run {
                    self.onSegmentReady?(aacData, effectiveStartTime, endTime, actualOverlapDuration)
                    self.delegate?.audioRecorder(self, didCaptureSegment: aacData, startTime: effectiveStartTime, endTime: endTime)

                    // Update start time for next segment
                    self.segmentStartTime = endTime
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.delegate?.audioRecorder(self, didFailWithError: error)
                }
            }
        }
    }
}

// MARK: - Audio Recorder Error

enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case engineCreationFailed
    case inputNodeUnavailable
    case formatCreationFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .engineCreationFailed:
            return "Failed to create audio engine"
        case .inputNodeUnavailable:
            return "Audio input not available"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .encodingFailed:
            return "Failed to encode audio"
        }
    }
}
