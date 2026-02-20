import SwiftUI
import AVFoundation

struct RecordingControlsView: View {
    @ObservedObject var cameraViewModel: CameraViewModel
    @Binding var recordingDuration: TimeInterval

    private var canRecord: Bool {
        if cameraViewModel.recordingMode == .screenOnly {
            return true
        } else {
            return cameraViewModel.isReady && cameraViewModel.isSessionRunning
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            VStack(spacing: 0) {
                // Top controls bar
                topControlsBar
                    .padding()

                // Layout picker for screenAndCamera mode
                if cameraViewModel.recordingMode == .screenAndCamera && !cameraViewModel.isRecording {
                    layoutPicker
                }

                // Preview area
                previewArea
                    .allowsHitTesting(false)

                if cameraViewModel.isRecording {
                    AudioLevelMeterView(audioLevel: cameraViewModel.audioLevel)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                Spacer()

                // Invisible spacer to reserve room for the floating buttons
                Color.clear.frame(height: 120)
            }

            // Floating buttons — always on top, always clickable
            recordingButtons
                .padding(.bottom, 40)
        }
        .onKeyPress(.escape) {
            print("[DEBUG-KEY] Escape pressed. isRecording=\(cameraViewModel.isRecording), isCountingDown=\(cameraViewModel.isCountingDown)")
            if cameraViewModel.isRecording || cameraViewModel.isCountingDown {
                cameraViewModel.stopRecording()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Top Controls

    private var topControlsBar: some View {
        HStack {
            Picker("Mode", selection: $cameraViewModel.recordingMode) {
                ForEach(RecordingMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .disabled(cameraViewModel.isRecording || cameraViewModel.isCountingDown)

            if cameraViewModel.recordingMode.needsCamera && cameraViewModel.availableCameras.count > 1 {
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
                .frame(maxWidth: 200)
                .disabled(cameraViewModel.isRecording || cameraViewModel.isCountingDown)
            }

            if cameraViewModel.recordingMode == .cameraOnly {
                Picker("Ratio", selection: $cameraViewModel.selectedAspectRatio) {
                    ForEach(AspectRatioOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 100)
                .disabled(cameraViewModel.isRecording || cameraViewModel.isCountingDown)
            }

            Picker("Resolution", selection: $cameraViewModel.selectedResolution) {
                ForEach(ResolutionOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 100)
            .disabled(cameraViewModel.isRecording || cameraViewModel.isCountingDown)

            if cameraViewModel.recordingMode.needsCamera {
                Button(action: {
                    cameraViewModel.isMirrored.toggle()
                }) {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .foregroundColor(cameraViewModel.isMirrored ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Mirror preview")

                Button(action: {
                    cameraViewModel.isGridVisible.toggle()
                }) {
                    Image(systemName: "grid")
                        .foregroundColor(cameraViewModel.isGridVisible ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Rule of thirds grid")
            }

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
    }

    // MARK: - Layout Picker

    private var layoutPicker: some View {
        HStack(spacing: 12) {
            Picker("Layout", selection: $cameraViewModel.selectedLayout) {
                ForEach(ScreenCameraLayout.allCases) { layout in
                    Label(layout.label, systemImage: layout.systemImage).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 350)

            if cameraViewModel.selectedLayout.isBubbleLayout {
                CameraBubblePositionPicker(selectedPosition: $cameraViewModel.bubblePosition)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Preview Area

    @ViewBuilder
    private var previewArea: some View {
        if cameraViewModel.recordingMode == .screenAndCamera && cameraViewModel.isRecording {
            CompositePreviewView(
                cameraViewModel: cameraViewModel,
                screenImage: cameraViewModel.screenFrame,
                layout: cameraViewModel.selectedLayout,
                bubblePosition: cameraViewModel.bubblePosition
            )
            .padding(.horizontal)
        } else if cameraViewModel.recordingMode == .screenOnly {
            if cameraViewModel.isRecording, let screenImage = cameraViewModel.screenFrame {
                Image(decorative: screenImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
                    .padding(.horizontal)
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .cornerRadius(12)
                    VStack(spacing: 12) {
                        Image(systemName: "display")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("Screen recording mode")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("Your entire screen will be captured")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
                .padding(.horizontal)
            }
        } else {
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
                .overlay(
                    Group {
                        if cameraViewModel.isGridVisible {
                            RuleOfThirdsGridView()
                        }
                    }
                )
        }
    }

    // MARK: - Recording Buttons

    private var recordingButtons: some View {
        HStack(spacing: 32) {
            if cameraViewModel.isRecording && cameraViewModel.recordingMode.needsCamera {
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
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                print("[DEBUG-BUTTON] Stop/Record button CLICKED. isRecording=\(cameraViewModel.isRecording), isCountingDown=\(cameraViewModel.isCountingDown)")
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
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canRecord && !cameraViewModel.isRecording && !cameraViewModel.isCountingDown)
            .opacity((canRecord || cameraViewModel.isRecording || cameraViewModel.isCountingDown) ? 1.0 : 0.5)
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

private struct RuleOfThirdsGridView: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let w = geometry.size.width
                let h = geometry.size.height

                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))

                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(Color.white.opacity(0.5), lineWidth: 1)
        }
        .allowsHitTesting(false)
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
