# Quick Cam — Testing Strategy

## Philosophy

Test business logic in Services and ViewModel. Camera and recording features require manual testing due to hardware dependencies.

## Stack

TBD — XCTest or Swift Testing (to be decided when tests are added).

## Coverage Targets

| Layer | Coverage | Approach |
|---|---|---|
| Models | Medium | Unit tests for data structures |
| Services | High | Unit tests with mocked dependencies |
| ViewModel | High | Integration tests with service mocks |
| Views | Low | Manual testing only |

## Per-Ticket Testing Checklist

For each ticket, verify:
- [ ] Project compiles with zero errors
- [ ] No new warnings introduced
- [ ] All existing features still work (see Manual Testing below)
- [ ] New code follows architecture rules from system-design.md

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
4. Open the exported file — verify 9:16 aspect ratio
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
