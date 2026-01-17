//
//  AudioWaveformView.swift
//  xiaojinpro
//
//  Animated audio waveform visualization
//

import SwiftUI

// MARK: - Audio Waveform View
struct AudioWaveformView: View {
    let amplitude: Float
    let isRecording: Bool

    @State private var phase: Double = 0
    private let barCount = 30

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    WaveformBar(
                        height: barHeight(for: index, in: geometry.size.height),
                        isRecording: isRecording
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            startAnimation()
        }
    }

    private func barHeight(for index: Int, in maxHeight: CGFloat) -> CGFloat {
        guard isRecording else {
            // Static bars when not recording
            return maxHeight * 0.2
        }

        // Create wave pattern based on amplitude
        let normalizedIndex = Double(index) / Double(barCount)
        let wave = sin(normalizedIndex * .pi * 2 + phase)
        let noise = Double.random(in: -0.3...0.3)

        // Combine wave, noise, and amplitude
        let amplitudeEffect = Double(amplitude) * 0.8
        let baseHeight = 0.15
        let height = baseHeight + (wave * 0.5 + 0.5) * amplitudeEffect + noise * amplitudeEffect * 0.3

        return CGFloat(max(0.1, min(1.0, height))) * maxHeight
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.linear(duration: 0.05)) {
                phase += 0.15
            }
        }
    }
}

// MARK: - Waveform Bar
struct WaveformBar: View {
    let height: CGFloat
    let isRecording: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(barColor)
            .frame(width: 4, height: height)
            .animation(.easeInOut(duration: 0.1), value: height)
    }

    private var barColor: Color {
        if isRecording {
            return .blue.opacity(0.8)
        } else {
            return .gray.opacity(0.4)
        }
    }
}

// MARK: - Circular Waveform View
struct CircularWaveformView: View {
    let amplitude: Float
    let isRecording: Bool

    @State private var animationPhase: Double = 0

    var body: some View {
        ZStack {
            // Background circles
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(
                        Color.blue.opacity(0.2 - Double(i) * 0.05),
                        lineWidth: 2
                    )
                    .scaleEffect(pulseScale(for: i))
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: animationPhase
                    )
            }

            // Main circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            isRecording ? .blue.opacity(0.6) : .gray.opacity(0.3),
                            isRecording ? .blue.opacity(0.2) : .gray.opacity(0.1)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)
                .scaleEffect(1.0 + CGFloat(amplitude) * 0.2)
                .animation(.easeInOut(duration: 0.1), value: amplitude)

            // Microphone icon
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .font(.system(size: 32))
                .foregroundColor(isRecording ? .white : .gray)
        }
        .onAppear {
            animationPhase = 1.0
        }
    }

    private func pulseScale(for index: Int) -> CGFloat {
        guard isRecording else { return 1.0 }
        let base = 1.2 + Double(index) * 0.15
        return CGFloat(base + Double(amplitude) * 0.1)
    }
}

// MARK: - Recording Timer View
struct RecordingTimerView: View {
    let time: TimeInterval
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Recording indicator
            Circle()
                .fill(isRecording ? Color.red : Color.gray)
                .frame(width: 8, height: 8)
                .opacity(isRecording ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isRecording)

            // Time display
            Text(formatTime(time))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(isRecording ? .primary : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.systemGray6))
        )
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 40) {
        AudioWaveformView(amplitude: 0.6, isRecording: true)
            .frame(height: 60)
            .padding()

        AudioWaveformView(amplitude: 0.3, isRecording: false)
            .frame(height: 60)
            .padding()

        CircularWaveformView(amplitude: 0.5, isRecording: true)
            .frame(width: 150, height: 150)

        RecordingTimerView(time: 125.5, isRecording: true)
    }
}
