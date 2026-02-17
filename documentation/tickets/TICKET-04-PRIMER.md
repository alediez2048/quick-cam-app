# TICKET-04: Extract Views into Separate Files

## Goal

Extract inline views from ContentView.swift and PreviewView.swift into individual files. Slim ContentView to pure layout orchestration.

## Prerequisites

TICKET-03 (Create CameraViewModel) must be complete.

## Files to Create

| File | Extracted From |
|---|---|
| `Views/CameraPreviewView.swift` | ContentView.swift — NSViewRepresentable + CameraPreviewNSView |
| `Views/RecordingControlsView.swift` | ContentView.swift — camera picker, record button, timer (new composition) |
| `Views/PreviousRecordingsSidebar.swift` | ContentView.swift — sidebar listing |
| `Views/PreviousRecordingCard.swift` | ContentView.swift — individual recording card |
| `Views/PreviousVideoPreview.swift` | ContentView.swift — full playback view |
| `Views/VideoPlayerView.swift` | PreviewView.swift — AVPlayerView wrapper |
| `Views/CroppedVideoPlayerView.swift` | PreviewView.swift — cropped AVPlayerLayer wrapper |

## ContentView After Extraction

ContentView should contain only:
- `@StateObject var cameraViewModel`
- Top-level HStack layout (sidebar + main area)
- Conditional rendering (camera controls vs preview vs previous video)
- Recording timer state management
- Target: ~100 lines

## Acceptance Criteria

- [ ] Seven new view files exist under `Views/`
- [ ] ContentView.swift is slimmed to layout orchestration
- [ ] PreviewView.swift delegates to extracted player views
- [ ] No business logic in any view
- [ ] Project compiles without errors
- [ ] All views render correctly
