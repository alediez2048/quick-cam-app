# Quick Cam App — Product Requirements Document (PRD)

**Version:** 2.0
**Date:** February 17, 2026
**Status:** Draft

---

## 1. Product Overview

### 1.1 Vision
Transform Quick Cam from a simple vertical video recorder into a comprehensive AI-powered video creation studio for content creators. Inspired by tools like Opus Clip and Riverside, Quick Cam will offer automated editing, AI captioning, AI B-roll, audio enhancement, and intelligent clip generation — all running natively on macOS.

### 1.2 Current State
Quick Cam is a macOS-native vertical video recorder built with SwiftUI and AVFoundation. It currently supports:
- Vertical (9:16) video recording with camera selection
- Basic speech-to-text captioning via Apple's Speech framework
- Video export to Downloads with caption overlays
- Recording management sidebar with thumbnails

### 1.3 Target Users
- Solo content creators (YouTube, TikTok, Instagram Reels)
- Podcasters needing video clips
- Educators creating short-form content
- Social media managers producing vertical video at scale

---

## 2. Current Technical Foundation

### 2.1 Tech Stack
| Layer | Technology |
|-------|-----------|
| UI | SwiftUI |
| Video Capture | AVFoundation (AVCaptureSession) |
| Video Processing | AVMutableComposition, AVAssetExportSession |
| Speech/Captions | Apple Speech Framework (SFSpeechRecognizer) |
| Text Rendering | QuartzCore (CATextLayer with keyframe animation) |
| Platform | macOS 14.0+ (Sonoma) |
| Architecture | MVVM + Services |

### 2.2 Architecture
```
Quick_Cam_AppApp (Entry)
└── ContentView (Root)
    ├── PreviousRecordingsSidebar
    ├── RecordingControlsView → CameraPreviewView
    ├── PreviewView → CroppedVideoPlayerView
    └── PreviousVideoPreview → VideoPlayerView

ViewModels/
└── CameraViewModel (coordinates all services)

Services/
├── CameraService (capture session management)
├── ExportService (video composition & export)
├── TranscriptionService (speech-to-text)
└── RecordingsRepository (file management)

Models/
├── RecordedVideo
└── TimedCaption
```

### 2.3 Current Entitlements & Permissions
- App Sandbox (enabled)
- Camera access
- Microphone access
- Downloads folder read/write
- Speech recognition

---

## 3. Feature Roadmap

### Phase 1: Enhanced Captioning & Audio (Foundation)
### Phase 2: AI-Powered Editing (Intelligence)
### Phase 3: Content Repurposing & Distribution (Scale)

---

## 4. Phase 1 — Enhanced Captioning & Audio

### 4.1 Advanced AI Captions

**Current state:** Basic 5-word caption chunks with fixed white-on-black styling.

**Requirements:**

| ID | Requirement | Priority |
|----|------------|----------|
| P1-CAP-01 | Multiple caption styles (Karaoke/word-highlight, Pop-up, Classic subtitle, Boxed) | Must |
| P1-CAP-02 | Word-level highlight animation (active word changes color as spoken) | Must |
| P1-CAP-03 | Customizable caption font, size, color, background, and position | Must |
| P1-CAP-04 | Multi-language transcription support (at minimum: English, Spanish, Portuguese, French, German, Japanese) | Must |
| P1-CAP-05 | Caption editing interface — allow users to correct transcription errors before export | Must |
| P1-CAP-06 | Emoji auto-insertion based on sentiment/keyword detection | Should |
| P1-CAP-07 | SRT/VTT export for captions as standalone files | Should |
| P1-CAP-08 | Auto-punctuation and sentence-level segmentation | Must |

**Caption Style Presets:**

- **Karaoke:** Words highlight one-by-one as spoken. Active word is a bold accent color, remaining words are white.
- **Pop-up:** Each word or phrase pops in with a scale animation. Previous words fade out.
- **Classic:** Standard subtitle bar at bottom of screen. Two lines max.
- **Boxed:** Individual words in rounded boxes that appear sequentially.

**Technical approach:**
- Continue using Apple Speech Framework for on-device transcription
- Add word-level timing from `SFTranscriptionSegment` (already available in the API)
- Build a `CaptionStyleEngine` service that renders different animation patterns via Core Animation
- Store caption style preferences in UserDefaults
- Create a `CaptionEditorView` with inline text editing bound to `TimedCaption` model

### 4.2 AI Audio Enhancement

**Current state:** Raw audio capture, no processing.

**Requirements:**

| ID | Requirement | Priority |
|----|------------|----------|
| P1-AUD-01 | Background noise removal (keyboard clicks, AC hum, fan noise) | Must |
| P1-AUD-02 | Audio normalization (consistent volume levels) | Must |
| P1-AUD-03 | Echo/reverb reduction | Should |
| P1-AUD-04 | Filler word detection and optional removal ("um", "uh", "like", "you know") | Should |
| P1-AUD-05 | Audio level meter during recording (visual feedback) | Must |
| P1-AUD-06 | Silence trimming (auto-detect and optionally cut dead air) | Should |

**Technical approach:**
- Use Apple's `AVAudioEngine` with audio processing taps for real-time monitoring
- Integrate `SoundAnalysis` framework for noise classification
- Use `vDSP` (Accelerate framework) for audio normalization and spectral processing
- Filler word detection via the existing Speech framework — mark filler segments and offer removal in a post-recording edit step
- Create an `AudioProcessingService` that runs as a pipeline: Denoise → Normalize → De-reverb

### 4.3 Recording Improvements

| ID | Requirement | Priority |
|----|------------|----------|
| P1-REC-01 | Pause/resume recording | Must |
| P1-REC-02 | Recording countdown timer (3-2-1) | Must |
| P1-REC-03 | Multiple aspect ratio support (9:16, 16:9, 1:1, 4:5) | Must |
| P1-REC-04 | Resolution selection (720p, 1080p, 4K) | Should |
| P1-REC-05 | Mirror/flip camera preview | Should |
| P1-REC-06 | Grid overlay toggle (rule of thirds) | Should |

---

## 5. Phase 2 — AI-Powered Editing

### 5.1 AI B-Roll Generation

**Requirements:**

| ID | Requirement | Priority |
|----|------------|----------|
| P2-BRL-01 | Analyze transcript to identify moments where B-roll would enhance the video | Must |
| P2-BRL-02 | Suggest and auto-insert relevant stock video/images from a built-in library | Must |
| P2-BRL-03 | Support user-provided B-roll media (drag-and-drop media library) | Must |
| P2-BRL-04 | Keyword-based B-roll matching (e.g., speaker says "ocean" → ocean footage) | Must |
| P2-BRL-05 | Smooth transitions (crossfade, cut) between main footage and B-roll | Should |
| P2-BRL-06 | AI-generated images as B-roll via on-device or API-based image generation | Could |

**Technical approach:**
- Build a `BRollService` that analyzes `TimedCaption` segments for noun/topic extraction using `NaturalLanguage` framework
- Create a local B-roll media index (JSON manifest) mapping keywords → media files
- Use `AVMutableComposition` multi-track layering to composite B-roll over primary video
- B-roll segments render as picture-in-picture or full-frame overlay with opacity transitions
- Optional: Integrate with a stock media API (Pexels, Pixabay) for on-demand downloads

### 5.2 Smart Clip Generation (Auto-Highlights)

**Requirements:**

| ID | Requirement | Priority |
|----|------------|----------|
| P2-CLG-01 | AI analyzes full recording and identifies the most engaging segments | Must |
| P2-CLG-02 | Generate multiple short clips (15s, 30s, 60s) from a single recording | Must |
| P2-CLG-03 | Score each clip on predicted engagement/virality | Should |
| P2-CLG-04 | Auto-apply captions and aspect ratio to generated clips | Must |
| P2-CLG-05 | Batch export all generated clips | Should |
| P2-CLG-06 | User can accept, reject, or adjust clip boundaries | Must |

**Technical approach:**
- Build a `ClipIntelligenceService` that scores segments based on:
  - Speech energy/emphasis (via audio amplitude analysis)
  - Keyword density (NaturalLanguage framework NER + sentiment)
  - Sentence completeness (avoid cutting mid-sentence)
  - Silence gaps (natural clip boundaries)
- Use `AVAssetExportSession` with time ranges to extract sub-clips
- Present clips in a `ClipReviewView` with thumbnails, scores, and trim handles

### 5.3 Text-Based Video Editing

**Requirements:**

| ID | Requirement | Priority |
|----|------------|----------|
| P2-TBE-01 | Display full transcript alongside video timeline | Must |
| P2-TBE-02 | Delete text from transcript to remove corresponding video/audio | Must |
| P2-TBE-03 | Click on transcript text to seek to that moment in video | Must |
| P2-TBE-04 | Highlight/select transcript sections to define clip boundaries | Should |
| P2-TBE-05 | Undo/redo for all text-based edits | Must |

**Technical approach:**
- Build a `TranscriptEditorView` with synchronized scrolling to video playback
- Map each word in transcript to a `CMTimeRange` via Speech framework segment data
- Deletions create "exclusion ranges" that are applied during composition (skip those time ranges in `AVMutableComposition`)
- Maintain an edit history stack for undo/redo

### 5.4 Video Filters & Effects

| ID | Requirement | Priority |
|----|------------|----------|
| P2-VFX-01 | Color grading presets (warm, cool, vintage, high contrast, B&W) | Should |
| P2-VFX-02 | Background blur (depth effect simulation) | Could |
| P2-VFX-03 | Speed ramping (slow-mo / fast-forward segments) | Should |
| P2-VFX-04 | Zoom-to-speaker effect (auto-zoom on active speaker) | Should |

**Technical approach:**
- Use `CIFilter` pipeline for color grading applied via `AVVideoComposition`
- Background blur via Core Image `CIGaussianBlur` with mask
- Speed changes via `CMTimeMapping` on composition tracks

---

## 6. Phase 3 — Content Repurposing & Distribution

### 6.1 Multi-Format Export

| ID | Requirement | Priority |
|----|------------|----------|
| P3-EXP-01 | Export as MP4 (H.264/H.265) in addition to MOV | Must |
| P3-EXP-02 | Export as GIF for short clips | Should |
| P3-EXP-03 | Audio-only export (MP3/WAV) for podcast use | Should |
| P3-EXP-04 | Custom export destination (not just Downloads) | Must |
| P3-EXP-05 | Export quality/compression presets (High, Medium, Web-optimized) | Must |
| P3-EXP-06 | Batch export with different aspect ratios from same source | Should |

### 6.2 AI Content Generation

| ID | Requirement | Priority |
|----|------------|----------|
| P3-AIG-01 | Auto-generate video title suggestions from transcript | Should |
| P3-AIG-02 | Generate social media descriptions/captions from transcript | Should |
| P3-AIG-03 | Generate show notes / summary from transcript | Should |
| P3-AIG-04 | Auto-generate chapter markers from topic changes | Should |

**Technical approach:**
- Integrate with an LLM API (Claude API) for text generation tasks
- Feed transcript text to API with structured prompts for each content type
- Present suggestions in a `ContentAssistantView` with copy-to-clipboard

### 6.3 Brand Kit & Templates

| ID | Requirement | Priority |
|----|------------|----------|
| P3-BRK-01 | Custom logo/watermark overlay with positioning | Should |
| P3-BRK-02 | Intro/outro templates (customizable bumper clips) | Could |
| P3-BRK-03 | Saved brand color palette applied to captions | Should |
| P3-BRK-04 | Save and reuse export presets (style + format + aspect ratio) | Should |

### 6.4 Project Management

| ID | Requirement | Priority |
|----|------------|----------|
| P3-PRJ-01 | Project-based organization (replace flat Downloads scanning) | Must |
| P3-PRJ-02 | Tags and search for recordings | Should |
| P3-PRJ-03 | Persistent app-managed storage with database (SQLite/SwiftData) | Must |
| P3-PRJ-04 | Import external video files for processing | Must |

**Technical approach:**
- Migrate from filesystem scanning to SwiftData for project/recording metadata
- Each project contains: source video, generated clips, captions, export settings
- App-managed storage directory within Application Support

---

## 7. Technical Architecture (Target State)

### 7.1 Updated Architecture
```
Quick_Cam_AppApp
└── ContentView
    ├── SidebarView (projects + recordings)
    ├── RecordingStudioView
    │   ├── CameraPreviewView
    │   ├── AudioLevelMeterView
    │   └── RecordingControlsView
    ├── EditorView
    │   ├── VideoTimelineView
    │   ├── TranscriptEditorView
    │   ├── CaptionStylePickerView
    │   ├── BRollBrowserView
    │   └── ClipReviewView
    └── ExportView
        ├── FormatSelectorView
        ├── ContentAssistantView
        └── BrandKitView

ViewModels/
├── CameraViewModel
├── EditorViewModel
├── CaptionViewModel
└── ExportViewModel

Services/
├── CameraService
├── AudioProcessingService      ← NEW
├── TranscriptionService        (enhanced: multi-language, word-level)
├── CaptionStyleEngine          ← NEW
├── BRollService                ← NEW
├── ClipIntelligenceService     ← NEW
├── ExportService               (enhanced: multi-format)
├── ContentGenerationService    ← NEW (LLM integration)
├── ProjectRepository           ← NEW (replaces RecordingsRepository)
└── MediaLibraryService         ← NEW

Models/
├── Project                     ← NEW
├── RecordedVideo
├── TimedCaption                (enhanced: word-level timing)
├── CaptionStyle                ← NEW
├── GeneratedClip               ← NEW
├── BRollSegment                ← NEW
└── ExportPreset                ← NEW
```

### 7.2 New Framework Dependencies
| Framework | Purpose | Phase |
|-----------|---------|-------|
| NaturalLanguage | Keyword extraction, sentiment, NER for B-roll matching and clip scoring | 2 |
| SoundAnalysis | Noise classification for audio enhancement | 1 |
| Accelerate (vDSP) | Audio signal processing (normalization, spectral analysis) | 1 |
| CoreImage | Video filters and color grading | 2 |
| SwiftData | Project persistence and metadata storage | 3 |
| UniformTypeIdentifiers | Multi-format file handling | 3 |

### 7.3 New Entitlements Required
| Entitlement | Reason | Phase |
|-------------|--------|-------|
| Network access | Stock B-roll downloads, LLM API calls | 2-3 |
| User-selected files (read/write) | Custom export destinations, media import | 3 |
| Application Support directory | Project storage | 3 |

---

## 8. UI/UX Direction

### 8.1 Editor Layout (Phase 2+)
```
┌──────────────────────────────────────────────────────┐
│ Toolbar: [Record] [Import] [Export] [Settings]       │
├────────┬─────────────────────────────┬───────────────┤
│        │                             │               │
│  Side  │     Video Preview           │  Inspector    │
│  bar   │     (9:16 preview)          │  Panel        │
│        │                             │  - Captions   │
│ Projects│                            │  - B-Roll     │
│ Library │                            │  - Filters    │
│ B-Roll  │                            │  - Audio      │
│        │                             │               │
│        ├─────────────────────────────┤               │
│        │  Transcript / Timeline      │               │
│        │  [word] [word] [word] ...   │               │
│        │  ▶──────●─────────────────  │               │
└────────┴─────────────────────────────┴───────────────┘
```

### 8.2 Design Principles
- **Progressive disclosure:** Recording mode stays simple. Editing tools appear only after recording.
- **Non-destructive editing:** All edits are reversible. Source video is never modified.
- **AI-first, human-final:** AI suggests, user approves. Every AI action can be overridden.
- **Keyboard-first:** Power users can drive the entire workflow with shortcuts.

---

## 9. Success Metrics

| Metric | Target |
|--------|--------|
| Export completion rate | > 90% (no crashes, no hangs) |
| Caption accuracy (WER) | < 10% word error rate |
| Time to first export (new user) | < 2 minutes |
| AI clip acceptance rate | > 60% of suggested clips accepted by user |
| Audio enhancement satisfaction | Measurable noise reduction on processed exports |

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Apple Speech Framework accuracy limitations | Poor captions reduce product value | Offer manual editing; consider Whisper integration as fallback |
| On-device processing performance for long videos | Slow exports, high memory usage | Stream-process in chunks; show progress with estimated time; set max duration guardrails |
| Stock B-roll API costs and availability | Feature becomes expensive to maintain | Cache aggressively; support user-provided media as primary path; API as enhancement |
| LLM API dependency for content generation | Adds network requirement and cost | Make AI content generation optional; local summarization as fallback |
| Scope creep across phases | Never ship | Strict phase gating — each phase must ship before next begins |

---

## 11. Implementation Priority (Recommended Build Order)

### Phase 1 (Foundation) — Estimated Scope: 8 features
1. Audio level meter during recording (P1-AUD-05)
2. Recording countdown timer (P1-REC-02)
3. Pause/resume recording (P1-REC-01)
4. Multiple aspect ratio support (P1-REC-03)
5. Advanced caption styles with word-level highlighting (P1-CAP-01, P1-CAP-02)
6. Caption customization UI (P1-CAP-03)
7. Multi-language transcription (P1-CAP-04)
8. Audio normalization and noise removal (P1-AUD-01, P1-AUD-02)

### Phase 2 (Intelligence) — Estimated Scope: 6 features
1. Text-based video editing (P2-TBE-01 through P2-TBE-05)
2. Caption editing interface (P1-CAP-05)
3. Filler word detection and removal (P1-AUD-04)
4. Smart clip generation with scoring (P2-CLG-01 through P2-CLG-06)
5. AI B-roll suggestions and insertion (P2-BRL-01 through P2-BRL-05)
6. Video filters and color grading (P2-VFX-01)

### Phase 3 (Scale) — Estimated Scope: 6 features
1. Project-based organization with SwiftData (P3-PRJ-01, P3-PRJ-03)
2. Import external videos (P3-PRJ-04)
3. Multi-format export (P3-EXP-01 through P3-EXP-05)
4. AI content generation via LLM (P3-AIG-01 through P3-AIG-04)
5. Brand kit and templates (P3-BRK-01 through P3-BRK-04)
6. Batch export (P3-EXP-06)

---

## 12. Competitive Feature Matrix

| Feature | Quick Cam (Current) | Quick Cam (Target) | Opus Clip | Riverside |
|---------|--------------------|--------------------|-----------|-----------|
| Vertical video recording | Yes | Yes | No (import only) | Yes |
| AI captions | Basic | Advanced (multi-style, multi-lang) | Advanced | Advanced |
| Word-level highlight | No | Yes | Yes | Yes |
| Audio enhancement | No | Yes (on-device) | No | Yes |
| Noise removal | No | Yes | No | Yes |
| AI B-roll | No | Yes | Yes | No |
| Smart clip generation | No | Yes | Yes (core feature) | Yes (Magic Clips) |
| Text-based editing | No | Yes | No | Yes |
| Filler word removal | No | Yes | Yes | No |
| Multi-format export | No (MOV only) | Yes (MOV, MP4, GIF) | Yes | Yes |
| Multi-track recording | No | No | No | Yes |
| Live streaming | No | No | No | Yes |
| Virality scoring | No | Yes | Yes | No |
| Brand kit | No | Yes | Yes | Yes |
| Runs locally/offline | Yes | Mostly (except LLM features) | No (cloud) | No (cloud) |
| Native macOS app | Yes | Yes | No (web) | No (web) |
| One-time purchase | TBD | TBD | No (subscription) | No (subscription) |

**Key differentiator:** Quick Cam is a **native macOS app** with **on-device AI processing** — no cloud uploads, no subscriptions for core features, no internet required for recording and editing. Privacy-first by design.

---

*End of PRD*
