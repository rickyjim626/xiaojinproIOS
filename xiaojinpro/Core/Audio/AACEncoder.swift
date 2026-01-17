//
//  AACEncoder.swift
//  xiaojinpro
//
//  Audio encoding:
//  - Real device: AAC (small, efficient)
//  - Simulator: WAV (compatibility fallback)
//

import AVFoundation
import Foundation

// MARK: - Audio Encoder

class AACEncoder {

    /// Returns the audio format being used
    static var audioFormat: String {
        #if targetEnvironment(simulator)
        return "wav"
        #else
        return "aac"
        #endif
    }

    /// Encode PCM samples to audio data
    static func encode(samples: [Float], sampleRate: Double = 16000) async throws -> Data {
        #if targetEnvironment(simulator)
        // Simulator: use WAV (no hardware AAC encoder)
        return try await encodeToWAV(samples: samples, sampleRate: sampleRate)
        #else
        // Real device: use AAC
        return try await encodeToAAC(samples: samples, sampleRate: sampleRate)
        #endif
    }

    // MARK: - AAC Encoding (Real Device)

    private static func encodeToAAC(samples: [Float], sampleRate: Double) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard !samples.isEmpty else {
                        throw AACEncoderError.emptySamples
                    }

                    // Create PCM format
                    guard let inputFormat = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: sampleRate,
                        channels: 1,
                        interleaved: false
                    ) else {
                        throw AACEncoderError.formatCreationFailed
                    }

                    // Create PCM buffer
                    let frameCount = AVAudioFrameCount(samples.count)
                    guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
                        throw AACEncoderError.bufferCreationFailed
                    }
                    pcmBuffer.frameLength = frameCount

                    if let channelData = pcmBuffer.floatChannelData?[0] {
                        for (index, sample) in samples.enumerated() {
                            channelData[index] = sample
                        }
                    }

                    // Write to temp file as M4A (AAC container)
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("m4a")

                    let settings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderBitRateKey: 64000
                    ]

                    let outputFile = try AVAudioFile(forWriting: tempURL, settings: settings)
                    try outputFile.write(from: pcmBuffer)

                    // Read back
                    let data = try Data(contentsOf: tempURL)
                    try? FileManager.default.removeItem(at: tempURL)

                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - WAV Encoding (Simulator Fallback)

    private static func encodeToWAV(samples: [Float], sampleRate: Double) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard !samples.isEmpty else {
                        throw AACEncoderError.emptySamples
                    }

                    // Convert Float32 to Int16
                    let int16Samples = samples.map { sample -> Int16 in
                        let clamped = max(-1.0, min(1.0, sample))
                        return Int16(clamped * Float(Int16.max))
                    }

                    // WAV header
                    let numChannels: UInt16 = 1
                    let bitsPerSample: UInt16 = 16
                    let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
                    let blockAlign = numChannels * (bitsPerSample / 8)
                    let dataSize = UInt32(int16Samples.count * 2)
                    let fileSize = 36 + dataSize

                    var data = Data()

                    // RIFF header
                    data.append(contentsOf: "RIFF".utf8)
                    data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
                    data.append(contentsOf: "WAVE".utf8)

                    // fmt subchunk
                    data.append(contentsOf: "fmt ".utf8)
                    data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
                    data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
                    data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
                    data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
                    data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
                    data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
                    data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

                    // data subchunk
                    data.append(contentsOf: "data".utf8)
                    data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

                    for sample in int16Samples {
                        data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
                    }

                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Error

enum AACEncoderError: Error, LocalizedError {
    case emptySamples
    case formatCreationFailed
    case converterCreationFailed
    case bufferCreationFailed
    case fileCreationFailed
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptySamples: return "No audio samples"
        case .formatCreationFailed: return "Failed to create format"
        case .converterCreationFailed: return "Failed to create converter"
        case .bufferCreationFailed: return "Failed to create buffer"
        case .fileCreationFailed: return "Failed to create file"
        case .conversionFailed(let msg): return "Conversion failed: \(msg)"
        }
    }
}
