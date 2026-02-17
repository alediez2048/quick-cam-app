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
                    .disabled(cameraViewModel.isRecording)
                }

                Spacer()

                if cameraViewModel.isRecording {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                            Text("REC")
                                .foregroundColor(.red)
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
                .aspectRatio(9/16, contentMode: .fit)
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

            Spacer()

            // Record button
            Button(action: {
                if cameraViewModel.isRecording {
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

                    if cameraViewModel.isRecording {
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
