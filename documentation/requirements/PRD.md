# Quick Cam — Product Requirements Document

## Vision

One-click vertical video recording for social media creators. Quick Cam removes friction from the record-export workflow by capturing, cropping to 9:16, and optionally adding auto-generated captions — all in a single native macOS app.

## User Persona

Content creators who record talking-head or demo videos for TikTok, Instagram Reels, or YouTube Shorts. They need fast 9:16 recordings without launching a full video editor.

## MVP Features (Implemented)

- **Camera capture** — Live preview from any connected camera (built-in or external)
- **Vertical export** — Automatic 9:16 center-crop at 2160x3840 (4K vertical)
- **Auto-captions** — Optional speech transcription via Apple Speech framework, burned into the export as timed subtitles
- **Recording management** — Sidebar listing previous QuickCam recordings from Downloads, with playback and delete

## Non-Goals

- Filters or visual effects
- Multi-track editing or timeline
- Cloud sync or sharing integrations
- Audio-only recording
- Custom export resolutions (fixed at 9:16 4K)

## Success Metrics

| Metric | Target |
|---|---|
| Export resolution | 2160x3840 (4K vertical) |
| App launch to recording | < 3 seconds |
| Caption accuracy | Matches Apple Speech framework quality |
| Export time (30s clip) | < 15 seconds |

## Technology Stack

- SwiftUI (macOS 14+)
- AVFoundation (capture & composition)
- Speech framework (SFSpeechRecognizer)
- Core Animation (caption overlay rendering)
