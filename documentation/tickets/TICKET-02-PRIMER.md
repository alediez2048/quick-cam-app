# TICKET-02: Extract Services from CameraManager

## Goal

Decompose the 679-line `CameraManager` into 4 focused services, each with a single responsibility.

## Prerequisites

TICKET-01 (Extract Models) must be complete.

## Files to Create

| File | Responsibility |
|---|---|
| `Services/CameraService.swift` | Camera discovery, AVCaptureSession configuration, start/stop session, switch camera, start/stop recording, AVCaptureFileOutputRecordingDelegate |
| `Services/ExportService.swift` | Video composition (AVMutableComposition), 9:16 crop transform, caption layer rendering, AVAssetExportSession |
| `Services/TranscriptionService.swift` | SFSpeechRecognizer setup, audio transcription, TimedCaption generation |
| `Services/RecordingsRepository.swift` | Load previous recordings from Downloads, delete recordings, generate thumbnails, discard temp recordings |

## Scope

- Extract logic from CameraManager into focused services
- Each service is a plain class (not ObservableObject — state management moves to ViewModel in TICKET-03)
- Exception: CameraService needs to be ObservableObject with @Published properties since it manages live session state

## Acceptance Criteria

- [ ] Four service files exist under `Services/`
- [ ] Each service has a clear, single responsibility
- [ ] No duplicate logic between services
- [ ] Project compiles without errors
