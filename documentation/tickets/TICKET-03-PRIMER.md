# TICKET-03: Create CameraViewModel Coordinator

## Goal

Create `CameraViewModel` that owns all services, exposes `@Published` state to views, and replaces `CameraManager`.

## Prerequisites

TICKET-02 (Extract Services) must be complete.

## File to Create

| File | Purpose |
|---|---|
| `ViewModels/CameraViewModel.swift` | ObservableObject coordinator that owns CameraService, ExportService, TranscriptionService, RecordingsRepository |

## Design

- CameraViewModel owns all 4 services
- Binds CameraService's `@Published` properties to its own via Combine `assign(to:)`
- Exposes all state views need: isRecording, recordedVideoURL, availableCameras, selectedCamera, error, isSessionRunning, isAuthorized, isReady, previousRecordings, isExporting, isTranscribing, transcriptionProgress
- Orchestrates cross-service workflows (e.g., export calls transcription if captions enabled, then calls export, then reloads recordings)
- Delegates to services for all actual work

## Scope

- Create CameraViewModel
- Update all views to use CameraViewModel instead of CameraManager
- Delete CameraManager.swift
- Update Xcode project file

## Acceptance Criteria

- [ ] CameraViewModel exists under `ViewModels/`
- [ ] All views reference CameraViewModel, not CameraManager
- [ ] CameraManager.swift is deleted
- [ ] Project compiles without errors
- [ ] All features work identically to before
