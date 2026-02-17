# TICKET-01: Extract Models

## Goal

Move `TimedCaption` and `RecordedVideo` structs from `CameraManager.swift` into separate files under `Models/`.

## Prerequisites

None — this is the first ticket.

## Files to Create

| File | Content |
|---|---|
| `Models/RecordedVideo.swift` | `RecordedVideo` struct (Identifiable, Equatable) |
| `Models/TimedCaption.swift` | `TimedCaption` struct with text, startTime, endTime |

## Scope

- Pure file extraction — no logic changes
- Remove model definitions from CameraManager.swift
- Add appropriate imports (CoreMedia for TimedCaption, AppKit for RecordedVideo)

## Acceptance Criteria

- [ ] Both model files exist under `Models/`
- [ ] Models are identical to originals (no behavior change)
- [ ] Project compiles without errors
- [ ] CameraManager still references models correctly
