# Quick Cam

[![CI](https://github.com/alediez2048/quick-cam-app/actions/workflows/ci.yml/badge.svg)](https://github.com/alediez2048/quick-cam-app/actions/workflows/ci.yml)

A native macOS recorder for short-form video. Record your camera, your screen, or both at once, then export in the aspect ratio your platform wants, with styled captions generated on device.

## Features

- **Three recording modes:** camera only, screen only, or screen and camera together. The combined mode offers three layouts (side by side, circle bubble, square bubble), and the bubble can go in any corner.
- **Four aspect ratios at export:** 9:16, 16:9, 1:1 and 4:5, cropped from the full-resolution recording.
- **Resolution choice:** 720p, 1080p or 4K capture.
- **On-device captions** with Apple's Speech framework, in English, Spanish, Portuguese, French, German or Japanese. Captions are timed per word and burned into the export.
- **Four caption styles:** karaoke (word highlight), pop-up, classic and boxed, with a choice of font and position.
- **Transcript editor:** fix any misheard word before export, with playback following the transcript.
- **Audio cleanup:** an optional denoise and loudness-normalisation pass (Accelerate) before export. If it fails, the original audio is kept.
- **Recordings library:** previous recordings in a sidebar, ready to replay or re-export.

Exports are saved to your Downloads folder as `.mov`.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later to build
- Permissions requested on first use: Camera, Microphone, Screen Recording (screen modes only) and Speech Recognition (captions only)

## Build and run

```bash
git clone https://github.com/alediez2048/quick-cam-app.git
cd quick-cam-app
open Quick-Cam-App.xcodeproj
```

Build and run with ⌘R. To run the tests from the command line:

```bash
xcodebuild test -project Quick-Cam-App.xcodeproj -scheme Quick-Cam-App \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

CI runs the same command on every push.

## How it works

1. **Capture.** `CameraService` runs the `AVCaptureSession`. `CameraRecordingService` writes camera frames with `AVAssetWriter` and starts the audio and video tracks on a shared clock, so they stay in sync. `ScreenCaptureService` captures the display with ScreenCaptureKit and `ScreenRecordingService` writes it to disk.
2. **Compose.** In screen-and-camera mode, `ScreenCameraCompositor` is a custom `AVVideoCompositing` implementation that draws both sources into one frame using the chosen layout.
3. **Transcribe.** `TranscriptionService` produces word-level timings with `SFSpeechRecognizer`, and `CaptionStyleEngine` turns them into animated caption layers.
4. **Export.** `ExportService` crops to the target aspect ratio, applies the caption layers through `AVVideoCompositionCoreAnimationTool`, and replaces the audio track with the cleaned-up version when audio processing is on.

## Project structure

```
Quick-Cam-App/
├── Models/        Recording mode, aspect ratio, resolution, caption style, languages
├── ViewModels/    CameraViewModel (app state), TranscriptPlaybackObserver
├── Views/         SwiftUI views: controls, previews, caption and transcript editors
├── Services/      Capture, screen recording, composition, transcription, audio, export
└── ContentView.swift, PreviewView.swift
Quick-Cam-AppTests/  Unit tests for the view model and audio processing
documentation/       System design and test notes
```

Logging goes through `os.Logger` (subsystem `com.quickcam.Quick-Cam-App`), so it shows in Console.app instead of stdout.

## Author

Jorge Alejandro Diez · [github.com/alediez2048](https://github.com/alediez2048)
