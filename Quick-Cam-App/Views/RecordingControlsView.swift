import SwiftUI
import AVFoundation

struct RecordingControlsView: View {
    @ObservedObject var cameraViewModel: CameraViewModel
    @Binding var recordingDuration: TimeInterval

    var body: some View {
        VStack(spacing: 0) {
            // Camera picker at top
            HStack {
                if cameraViewModel.availableCameras.count > 1 {
                    Picker("Camera", selection: Binding(
                        get: { cameraViewModel.selectedCamera },
                        set: { newCamera in
                            if let camera = newCamera {
                                cameraViewModel.switchCamera(to: camera)
                            }
                        }
                    )) {
                        ForEach(cameraViewModel.availableCameras, id: \.uniqueID) { camera in
                            Text(camera.localizedName).tag(camera as AVCaptureDevice?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 250)
                    .disabled(cameraViewModel.isRecording || cameraViewModel.isCountingDown)
                }

                Picker("Ratio", selection: $cameraViewModel.selectedAspectRatio) {
                    ForEach(AspectRatioOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 100)
                .disabled(cameraViewModel.isRecording || cameraViewModel.isCountingDown)

                Spacer()

                if cameraViewModel.isRecording {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(cameraViewModel.isPaused ? .yellow : .red)
                                .frame(width: 10, height: 10)
                            Text(cameraViewModel.isPaused ? "PAUSED" : "REC")
                                .foregroundColor(cameraViewModel.isPaused ? .yellow : .red)
                                .fontWeight(.bold)
                        }
                        Text(formatDuration(recordingDuration))
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6))
                    .cornerRadius(6)
                }
            }
            .padding()

            // Camera preview
            CameraPreviewView(cameraViewModel: cameraViewModel)
                .aspectRatio(cameraViewModel.selectedAspectRatio.ratio, contentMode: .fit)
                .cornerRadius(12)
                .padding(.horizontal)
                .overlay(
                    Group {
                        if !cameraViewModel.isAuthorized {
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 40))
                                Text("Camera access required")
                                    .font(.headline)
                                Text("Please allow camera access to use Quick Cam")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundColor(.white)
                            .padding()
                        } else if !cameraViewModel.isReady || !cameraViewModel.isSessionRunning {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                Text("Starting camera...")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                )
                .overlay(
                    Group {
                        if cameraViewModel.isCountingDown {
                            CountdownOverlayView(value: cameraViewModel.countdownValue)
                        }
                    }
                )

            if cameraViewModel.isRecording {
                AudioLevelMeterView(audioLevel: cameraViewModel.audioLevel)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            Spacer()

            // Record / Pause / Stop buttons
            HStack(spacing: 32) {
                if cameraViewModel.isRecording {
                    // Pause / Resume button
                    Button(action: {
                        if cameraViewModel.isPaused {
                            cameraViewModel.resumeRecording()
                        } else {
                            cameraViewModel.pauseRecording()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: cameraViewModel.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Record / Stop button
                Button(action: {
                    if cameraViewModel.isRecording || cameraViewModel.isCountingDown {
                        cameraViewModel.stopRecording()
                    } else {
                        cameraViewModel.startRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 4)
                            .foregroundColor(.white)
                            .frame(width: 72, height: 72)

                        if cameraViewModel.isRecording || cameraViewModel.isCountingDown {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.red)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(.red)
                                .frame(width: 56, height: 56)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!cameraViewModel.isReady || !cameraViewModel.isSessionRunning)
                .opacity(cameraViewModel.isReady && cameraViewModel.isSessionRunning ? 1.0 : 0.5)
            }
            .padding(.bottom, 40)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

private struct AudioLevelMeterView: View {
    let audioLevel: Float

    private var normalizedLevel: CGFloat {
        // Map dBFS range -60...0 to 0...1
        let clamped = min(max(CGFloat(audioLevel), -60), 0)
        return (clamped + 60) / 60
    }

    private var meterColor: Color {
        if audioLevel > -3 {
            return .red
        } else if audioLevel > -12 {
            return .yellow
        } else {
            return .green
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))

                Capsule()
                    .fill(meterColor)
                    .frame(width: geometry.size.width * normalizedLevel)
                    .animation(.linear(duration: 0.06), value: normalizedLevel)
            }
        }
        .frame(height: 8)
    }
}

struct CountdownOverlayView: View {
    let value: Int

    var body: some View {
        if value > 0 {
            Text("\(value)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
                .id(value)
                .transition(.scale.combined(with: .opacity))
                .animation(.easeOut(duration: 0.3), value: value)
        }
    }
}
