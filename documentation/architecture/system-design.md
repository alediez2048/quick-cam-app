# Quick Cam — System Design

## Data Flow

```
Camera Input (AVCaptureSession)
  → AVCaptureMovieFileOutput → temp .mov file
    → Preview (AVPlayer in CroppedVideoPlayerView)
      → Export Pipeline:
          AVMutableComposition
          + 9:16 crop via CGAffineTransform
          + optional CATextLayer caption overlay with keyframe animation
          → AVAssetExportSession → Downloads folder
```

## State Ownership

```
CameraViewModel (@Published state)
  ├── CameraService        → session state, recording state, camera list
  ├── ExportService         → stateless, called with parameters
  ├── TranscriptionService  → stateless, async transcription
  └── RecordingsRepository  → stateless, file I/O operations

Views observe CameraViewModel via @StateObject / @ObservedObject
```

All `@Published` properties live on `CameraViewModel`. Services are owned by the ViewModel and do not publish state directly to views.

## Architecture Rules

1. **Single responsibility** — Each service handles one domain. No god objects.
2. **Threading model** — AVFoundation work runs on `sessionQueue` (serial DispatchQueue). UI updates dispatch to `MainActor`. Export uses Swift `Task`.
3. **File I/O** — All file operations (load, save, delete, thumbnail generation) go through `RecordingsRepository`.
4. **Thin views** — Views contain layout and user interaction only. No business logic, no direct AVFoundation calls.
5. **Coordinator pattern** — `CameraViewModel` orchestrates service calls and exposes unified state.

## Technology Choices

| Technology | Why |
|---|---|
| SwiftUI | Declarative UI, rapid iteration, native macOS |
| AVFoundation | Full control over capture session, composition, and export pipeline |
| Speech framework | On-device transcription, no external API dependency |
| NSViewRepresentable | Bridge AVCaptureVideoPreviewLayer and AVPlayerView/AVPlayerLayer into SwiftUI |
| Combine | Bind CameraService published state to CameraViewModel |

## Module Structure

```
Quick-Cam-App/
├── Quick_Cam_AppApp.swift          App entry point
├── ContentView.swift               Main layout orchestration
├── PreviewView.swift               Post-recording preview
├── Models/
│   ├── RecordedVideo.swift         Video metadata + thumbnail
│   └── TimedCaption.swift          Caption text with time range
├── Services/
│   ├── CameraService.swift         AVCaptureSession management
│   ├── ExportService.swift         Video composition & export
│   ├── TranscriptionService.swift  Speech-to-text
│   └── RecordingsRepository.swift  File I/O & thumbnails
├── ViewModels/
│   └── CameraViewModel.swift       State coordinator
└── Views/
    ├── CameraPreviewView.swift     Live camera NSViewRepresentable
    ├── RecordingControlsView.swift  Record button, timer, camera picker
    ├── PreviousRecordingsSidebar.swift  Sidebar listing
    ├── PreviousRecordingCard.swift  Individual recording card
    ├── PreviousVideoPreview.swift   Full playback view
    ├── VideoPlayerView.swift        AVPlayerView wrapper
    └── CroppedVideoPlayerView.swift Cropped AVPlayerLayer wrapper
```
