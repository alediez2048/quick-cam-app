# Quick Cam — AI Assistant Context

## What We're Building

Quick Cam is a macOS SwiftUI app for one-click vertical (9:16) video recording with optional auto-generated captions. It targets social media creators who need fast recordings for TikTok, Reels, and Shorts without a full video editor.

## Architecture

MVVM + Services pattern:
- **CameraViewModel** coordinates all services and exposes `@Published` state to views
- **CameraService** — AVCaptureSession lifecycle (discover, configure, start, stop, record)
- **ExportService** — AVMutableComposition with 9:16 crop + caption overlay → Downloads
- **TranscriptionService** — SFSpeechRecognizer audio-to-text
- **RecordingsRepository** — File I/O for previous recordings (load, delete, thumbnails)
- **Views** are thin — layout and user interaction only, no business logic

## Priorities

1. Working camera capture and recording
2. Correct 9:16 export at 4K (2160x3840)
3. Clean architecture with single-responsibility services
4. Optional caption generation

## Critical Constraints

- **macOS sandbox** — Camera, microphone, and speech recognition require user permission. Check `Info.plist` usage descriptions and entitlements.
- **Threading** — Never access AVCaptureSession on the main thread. Use `sessionQueue`. Always dispatch UI updates to MainActor.
- **File access** — Recordings are saved to and loaded from the user's Downloads directory only.
- **NSViewRepresentable** — Camera preview and video players bridge AppKit views into SwiftUI. Handle layout in `layout()` override.

## DO NOT

- Use UIKit (this is macOS, use AppKit/SwiftUI)
- Put business logic in Views
- Access AVCaptureSession on the main thread
- Hardcode file paths — always use FileManager APIs
- Skip permission checks for camera/microphone/speech
- Create retain cycles — use `[weak self]` in closures and callbacks
- Add unnecessary dependencies — the app uses only Apple frameworks
