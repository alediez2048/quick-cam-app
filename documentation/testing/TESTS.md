# Quick Cam: Testing

## Automated tests

XCTest, in `Quick-Cam-AppTests/`. CI runs them on every push with:

```bash
xcodebuild test -project Quick-Cam-App.xcodeproj -scheme Quick-Cam-App \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

| File | What it covers |
|---|---|
| `AudioProcessingServiceTests.swift` | The audio cleanup pipeline: steps run in order, output files are valid audio of the same length, denoise lowers the noise floor while keeping a speech-like tone, and normalize lifts quiet audio without clipping. |
| `CameraViewModelTests.swift` | Recording state: the countdown, cancelling during the countdown, pause and resume, and the audio level the UI shows. The camera is replaced by `MockCameraService`. |

Capture, screen recording and export depend on real cameras, screens and permissions, so they are checked by hand with the steps below.

## Manual Testing Procedures

### Camera Preview
1. Launch the app
2. Verify camera preview appears within 3 seconds
3. If multiple cameras available, switch cameras via picker
4. Verify preview updates to new camera

### Recording
1. Click the record button (red circle)
2. Verify REC indicator and timer appear
3. Record for at least 5 seconds
4. Click stop (red square)
5. Verify preview screen appears with recorded video

### Export
1. After recording, enter an optional title
2. Click Save
3. Verify file appears in Downloads folder
4. Open the exported file and check it has the aspect ratio you picked (9:16, 16:9, 1:1 or 4:5)
5. Verify video plays correctly

### Captions
1. Record a clip with speech
2. Enable "Auto-generate captions" toggle
3. Click Save
4. Open exported file — verify captions appear at correct times

### Previous Recordings
1. Verify sidebar shows previously exported recordings
2. Click a recording — verify it plays back
3. Hover over a recording card — verify delete button appears
4. Delete a recording — verify it disappears from sidebar and file is removed
