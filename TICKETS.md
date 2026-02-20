# Quick Cam App — Ticket Backlog

Generated from PRD v2.0 — February 17, 2026

---

## Phase 1: Enhanced Captioning & Audio (Foundation)

### Recording Improvements

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-001 | **Add recording countdown timer (3-2-1)** | P1-REC-02 | Must | — |
| | Display an animated 3-2-1 countdown overlay after the user presses record, before capture actually begins. Include optional sound tick. | | | |
| QC-002 | **Implement pause/resume recording** | P1-REC-01 | Must | — |
| | Add a pause button during active recording. Pausing stops capture without finalizing the file. Resuming appends to the same session. Update the recording timer to reflect paused time. Requires changes to `CameraService` to support `pauseRecording()` / `resumeRecording()`. | | | |
| QC-003 | **Support multiple aspect ratios (9:16, 16:9, 1:1, 4:5)** | P1-REC-03 | Must | — |
| | Add an aspect ratio picker to the recording controls. Update `CameraPreviewView` to crop/letterbox the preview to the selected ratio. Update `ExportService` to compose the output at the chosen dimensions. Supported ratios: 9:16 (2160x3840), 16:9 (3840x2160), 1:1 (2160x2160), 4:5 (2160x2700). | | | |
| QC-004 | **Add resolution selection (720p, 1080p, 4K)** | P1-REC-04 | Should | — |
| | Add a resolution picker in recording settings. Map selections to AVCaptureSession presets. Persist selection in UserDefaults. Gracefully fall back if selected resolution is unavailable on the current camera. | | | |
| QC-005 | **Add mirror/flip camera preview toggle** | P1-REC-05 | Should | — |
| | Add a toggle button to horizontally flip the camera preview layer. Mirror only affects the preview, not the recorded output (unless user opts in). | | | |
| QC-006 | **Add rule-of-thirds grid overlay** | P1-REC-06 | Should | — |
| | Add a toggle button that overlays a 3x3 grid on `CameraPreviewView`. Grid lines should be semi-transparent white. Persist toggle state in UserDefaults. | | | |

### Audio Enhancement

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-007 | **Add real-time audio level meter** | P1-AUD-05 | Must | — |
| | Display a visual audio level meter during recording showing current input volume. Use `AVAudioEngine` with an audio tap to read RMS levels. Show a vertical bar or waveform indicator near the recording controls. Warn visually if levels are clipping. | | | |
| QC-008 | **Create AudioProcessingService scaffold** | P1-AUD-01 | Must | — |
| | Create a new `AudioProcessingService` with a pipeline architecture: input → denoise → normalize → output. Define the protocol for processing steps. Accept an audio file URL, process it, and output a new processed file. This service will be called during export. | | | |
| QC-009 | **Implement background noise removal** | P1-AUD-01 | Must | QC-008 |
| | Add noise removal as the first step in `AudioProcessingService`. Use `vDSP` spectral analysis to identify and suppress consistent background noise (fan hum, AC, keyboard). Apply spectral gating/subtraction. Integrate `SoundAnalysis` framework for noise classification to improve targeting. | | | |
| QC-010 | **Implement audio normalization** | P1-AUD-02 | Must | QC-008 |
| | Add loudness normalization as a processing step. Analyze peak and RMS levels of the full audio track. Apply gain adjustment to hit a target loudness (e.g., -16 LUFS for social media). Use `vDSP` for gain application. Prevent clipping with a limiter. | | | |
| QC-011 | **Implement echo/reverb reduction** | P1-AUD-03 | Should | QC-008 |
| | Add de-reverb as a processing step in `AudioProcessingService`. Use spectral analysis to identify and reduce room reverb and echo artifacts. Lower priority than noise removal and normalization. | | | |
| QC-012 | **Add audio enhancement toggle to export flow** | P1-AUD-01 | Must | QC-008, QC-009, QC-010 |
| | Add an "Enhance Audio" toggle in `PreviewView` next to the existing captions toggle. When enabled, run the audio through `AudioProcessingService` before compositing in `ExportService`. Show progress indicator during processing. | | | |

### Advanced Captions

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-013 | **Upgrade TranscriptionService to word-level timing** | P1-CAP-02 | Must | — |
| | Refactor `TranscriptionService` to return word-level `TimedCaption` entries (one per word) instead of 5-word chunks. Use `SFTranscriptionSegment` data which already provides per-word timestamps. Update `TimedCaption` model to include a `words: [TimedWord]` array with individual timing. | | | |
| QC-014 | **Create CaptionStyle model and presets** | P1-CAP-01 | Must | — |
| | Create a `CaptionStyle` model with properties: `styleName`, `fontName`, `fontSize`, `textColor`, `highlightColor`, `backgroundColor`, `position` (top/center/bottom), `animationType` (enum: karaoke, popup, classic, boxed). Define 4 built-in presets. Persist user preference in UserDefaults. | | | |
| QC-015 | **Build CaptionStyleEngine service** | P1-CAP-01 | Must | QC-013, QC-014 |
| | Create a `CaptionStyleEngine` service that takes `[TimedCaption]` and a `CaptionStyle` and generates the appropriate `CALayer` hierarchy for the export composition. Implement rendering logic for each animation type: Karaoke (word-level color change), Pop-up (scale animation), Classic (static subtitle bar), Boxed (rounded rect per word). | | | |
| QC-016 | **Build caption style picker UI** | P1-CAP-03 | Must | QC-014, QC-015 |
| | Create a `CaptionStylePickerView` shown in `PreviewView` when captions are enabled. Display visual previews of each style preset. Allow customization of font, size, text color, highlight color, background color, and position. Show a live preview of the selected style on the video. | | | |
| QC-017 | **Add multi-language transcription support** | P1-CAP-04 | Must | QC-013 |
| | Add a language selector dropdown to `PreviewView`. Support at minimum: English, Spanish, Portuguese, French, German, Japanese. Initialize `SFSpeechRecognizer` with the selected locale. Check `isAvailable` for the chosen locale and show a warning if unsupported on the user's system. Persist last-used language. | | | |
| QC-018 | **Add auto-punctuation and sentence segmentation** | P1-CAP-08 | Must | QC-013 |
| | Enhance transcription output to include proper punctuation. Apple Speech Framework provides punctuation in `bestTranscription.formattedString` — use this to punctuate individual segments. Group words into sentence-level caption blocks using punctuation boundaries instead of fixed 5-word chunks. | | | |
| QC-019 | **Add emoji auto-insertion for captions** | P1-CAP-06 | Should | QC-013, QC-018 |
| | Analyze caption text for keywords/sentiment and optionally insert relevant emojis. Use a keyword → emoji mapping (e.g., "love" → heart, "fire" → flame, "laugh" → face). Add a toggle to enable/disable emoji insertion. Keep it subtle — max one emoji per caption segment. | | | |
| QC-020 | **Export captions as SRT/VTT files** | P1-CAP-07 | Should | QC-013 |
| | Add an option during export to save captions as a standalone `.srt` and/or `.vtt` file alongside the video. Format the `TimedCaption` data into standard subtitle file formats with proper timestamp formatting. | | | |

---

## Phase 2: AI-Powered Editing (Intelligence)

### Text-Based Editing

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-021 | **Build TranscriptEditorView with video sync** | P2-TBE-01, P2-TBE-03 | Must | QC-013 |
| | Create a `TranscriptEditorView` that displays the full transcript as selectable text. Highlight the current word during video playback. Clicking a word seeks the video to that word's timestamp. Scroll position follows playback. | | | |
| QC-022 | **Implement text-based deletion (edit by transcript)** | P2-TBE-02 | Must | QC-021 |
| | Allow users to select and delete words/sentences from the transcript. Deleted text creates exclusion `CMTimeRange` entries. During export, these ranges are skipped in `AVMutableComposition`. Deleted text appears as strikethrough in the editor until export. | | | |
| QC-023 | **Add undo/redo for text-based edits** | P2-TBE-05 | Must | QC-022 |
| | Implement an edit history stack (undo/redo) for all transcript modifications. Support Cmd+Z / Cmd+Shift+Z keyboard shortcuts. Track deletions, restorations, and clip boundary changes. | | | |
| QC-024 | **Add transcript selection for clip boundaries** | P2-TBE-04 | Should | QC-021 |
| | Allow users to highlight/select a range of transcript text to define a clip boundary. Selected range maps to a `CMTimeRange`. Integrate with the clip generation flow (QC-029) so users can manually define clips from transcript. | | | |

### Caption Editing

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-025 | **Build caption editing interface** | P1-CAP-05 | Must | QC-013, QC-021 |
| | Create a `CaptionEditorView` (can be part of `TranscriptEditorView`) that allows users to edit transcription text inline before export. Edits update the `TimedCaption` model. Support correcting misheard words, adding/removing punctuation, and splitting/merging caption segments. | | | |

### Filler Word Removal

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-026 | **Detect and highlight filler words in transcript** | P1-AUD-04 | Should | QC-013, QC-021 |
| | After transcription, scan for filler words ("um", "uh", "like", "you know", "basically", "actually"). Highlight them in the transcript editor with a distinct color. Show a count of detected fillers. | | | |
| QC-027 | **Implement one-click filler word removal** | P1-AUD-04 | Should | QC-026, QC-022 |
| | Add a "Remove Fillers" button that automatically selects all detected filler word segments and adds them to the exclusion ranges. User can review and restore individual fillers before export. | | | |

### Smart Clip Generation

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-028 | **Build ClipIntelligenceService** | P2-CLG-01 | Must | QC-013 |
| | Create a `ClipIntelligenceService` that analyzes a recording and scores segments for engagement. Scoring factors: speech energy (audio amplitude via `vDSP`), keyword density (`NaturalLanguage` NER + sentiment), sentence completeness, silence gaps as natural boundaries. Output: array of `GeneratedClip` with time ranges and scores. | | | |
| QC-029 | **Generate short clips from recordings (15s, 30s, 60s)** | P2-CLG-02 | Must | QC-028 |
| | Using `ClipIntelligenceService` scores, generate candidate clips at 15s, 30s, and 60s durations. Ensure clips start and end at sentence boundaries. Rank by engagement score. Generate up to 10 candidates per duration. | | | |
| QC-030 | **Build ClipReviewView** | P2-CLG-06 | Must | QC-029 |
| | Create a `ClipReviewView` displaying generated clips with: thumbnail preview, engagement score badge, duration, transcript excerpt. Users can accept, reject, or adjust clip start/end with trim handles. Accepted clips queue for export. | | | |
| QC-031 | **Add virality/engagement scoring display** | P2-CLG-03 | Should | QC-028 |
| | Display a visual score (1-100 or star rating) on each generated clip. Show a breakdown tooltip explaining why the clip scored high/low (e.g., "Strong keywords", "High energy", "Good pacing"). | | | |
| QC-032 | **Auto-apply captions to generated clips** | P2-CLG-04 | Must | QC-029, QC-015 |
| | When exporting a generated clip, automatically apply the user's chosen caption style. Subset the transcript to the clip's time range. Apply the same `CaptionStyleEngine` rendering used for full exports. | | | |
| QC-033 | **Batch export generated clips** | P2-CLG-05 | Should | QC-030, QC-032 |
| | Add a "Export All" button in `ClipReviewView` that exports all accepted clips sequentially. Show progress (e.g., "Exporting clip 3 of 7"). Each clip gets its own file with captions and aspect ratio applied. | | | |

### AI B-Roll

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-034 | **Build BRollService with keyword extraction** | P2-BRL-01, P2-BRL-04 | Must | QC-013 |
| | Create a `BRollService` that analyzes `TimedCaption` segments using `NaturalLanguage` framework. Extract nouns, named entities, and topics. Identify segments where visual variety would improve engagement (e.g., long talking-head stretches). Output: array of `BRollSegment` with time ranges and matched keywords. | | | |
| QC-035 | **Build local B-roll media library** | P2-BRL-02, P2-BRL-03 | Must | QC-034 |
| | Create a `MediaLibraryService` with a local media index (JSON manifest) mapping keywords to media files. Support user drag-and-drop to add custom B-roll media. Store media in app's Application Support directory. Index media by user-assigned tags and auto-detected content. | | | |
| QC-036 | **Build B-roll browser UI** | P2-BRL-02 | Must | QC-035 |
| | Create a `BRollBrowserView` showing suggested B-roll placements on a timeline. Display keyword matches and suggested media. Users can accept, reject, or swap suggested B-roll. Support drag-and-drop from Finder to add new media. | | | |
| QC-037 | **Composite B-roll into video export** | P2-BRL-05 | Must | QC-034, QC-035 |
| | Update `ExportService` to support multi-track composition with B-roll. Insert B-roll clips at designated time ranges as full-frame overlays or picture-in-picture. Apply crossfade transitions (0.3s default) between main footage and B-roll segments. | | | |
| QC-038 | **Integrate stock media API for B-roll** | P2-BRL-02 | Should | QC-035, QC-036 |
| | Add optional integration with a free stock media API (Pexels or Pixabay). Search by extracted keywords. Download and cache results locally. Requires network entitlement. Show attribution as required by API terms. | | | |

### Video Filters & Effects

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-039 | **Implement color grading presets** | P2-VFX-01 | Should | — |
| | Create 5 color grading presets using `CIFilter` chains: Warm, Cool, Vintage, High Contrast, B&W. Apply via `AVVideoComposition` custom compositor. Add a filter picker in the editor with thumbnail previews of each preset applied to a frame from the current video. | | | |
| QC-040 | **Implement speed ramping** | P2-VFX-03 | Should | QC-022 |
| | Allow users to mark segments for slow-motion (0.5x) or fast-forward (2x, 4x). Apply via `CMTimeMapping` on composition tracks. Adjust audio pitch accordingly or mute during speed changes. Integrate with the transcript timeline for easy segment selection. | | | |
| QC-041 | **Implement zoom-to-speaker effect** | P2-VFX-04 | Should | — |
| | Detect audio energy peaks to identify speaking moments. Auto-apply a subtle zoom (1.0x → 1.2x) with smooth ease-in/ease-out during high-energy speech. Apply as a transform animation on the video composition layer. | | | |

---

## Phase 3: Content Repurposing & Distribution (Scale)

### Project Management

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-042 | **Create Project model with SwiftData** | P3-PRJ-01, P3-PRJ-03 | Must | — |
| | Define a `Project` SwiftData model containing: title, creation date, source video URL, generated clips, caption data, export settings, tags. Set up SwiftData model container in the app entry point. Migrate from filesystem-based `RecordingsRepository` to `ProjectRepository`. | | | |
| QC-043 | **Build project-based sidebar** | P3-PRJ-01 | Must | QC-042 |
| | Replace `PreviousRecordingsSidebar` with a project-based sidebar. Display projects with thumbnails, titles, dates. Support creating, renaming, and deleting projects. Show project status (draft, exported, etc.). | | | |
| QC-044 | **Implement external video import** | P3-PRJ-04 | Must | QC-042 |
| | Add an "Import" button that opens a file picker for `.mov`, `.mp4`, `.m4v` files. Copy imported video into app-managed storage. Create a new project from the imported file. Process the video through the same transcription and editing pipeline. Requires user-selected files entitlement. | | | |
| QC-045 | **Add tags and search for projects** | P3-PRJ-02 | Should | QC-042, QC-043 |
| | Allow users to tag projects with custom labels. Add a search bar to the sidebar that filters by title and tags. Persist tags in SwiftData. | | | |

### Multi-Format Export

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-046 | **Add MP4 export (H.264/H.265)** | P3-EXP-01 | Must | — |
| | Add MP4 as an export format option alongside MOV. Use `AVAssetExportSession` with `.mp4` output file type. Support both H.264 and H.265 (HEVC) codecs. Default to H.264 for maximum compatibility. | | | |
| QC-047 | **Add custom export destination** | P3-EXP-04 | Must | — |
| | Replace hardcoded Downloads folder with a save panel (`NSSavePanel`). Remember last-used directory. Still default to Downloads but allow user to choose any writable location. Requires user-selected files entitlement. | | | |
| QC-048 | **Add export quality/compression presets** | P3-EXP-05 | Must | QC-046 |
| | Create an `ExportPreset` model with options: High (original quality), Medium (balanced), Web-optimized (small file size). Map presets to `AVAssetExportSession` preset names and video bitrate settings. Show estimated file size before export. | | | |
| QC-049 | **Add audio-only export (MP3/WAV)** | P3-EXP-03 | Should | — |
| | Add an "Audio Only" export option that extracts and exports just the audio track. Support WAV (lossless) and MP3 (compressed) formats. Apply audio enhancements if enabled. Useful for podcast repurposing. | | | |
| QC-050 | **Add GIF export for short clips** | P3-EXP-02 | Should | — |
| | Add GIF as an export option for clips under 15 seconds. Use `CGImageDestination` with `kUTTypeGIF` to create animated GIFs. Allow frame rate selection (10/15/20 fps). Show file size preview. | | | |
| QC-051 | **Implement batch export with multiple aspect ratios** | P3-EXP-06 | Should | QC-003, QC-046 |
| | Add a "Batch Export" option that exports the same video in multiple aspect ratios and/or formats in one operation. User selects combinations (e.g., 9:16 MP4 + 1:1 MP4 + 16:9 MOV). Show progress for each export. | | | |

### AI Content Generation

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-052 | **Integrate Claude API for content generation** | P3-AIG-01 | Should | QC-013 |
| | Create a `ContentGenerationService` that sends transcript text to the Claude API. Handle API key management (stored in Keychain). Support structured prompts for different content types. Requires network entitlement. | | | |
| QC-053 | **Auto-generate video title suggestions** | P3-AIG-01 | Should | QC-052 |
| | After transcription, offer AI-generated title suggestions. Send transcript to Claude API with a prompt requesting 3-5 concise, engaging title options. Display suggestions in the title input field as selectable chips. | | | |
| QC-054 | **Generate social media descriptions** | P3-AIG-02 | Should | QC-052 |
| | Add a "Generate Description" button in the export view. Create platform-specific descriptions (Twitter/X, Instagram, YouTube, TikTok) with appropriate length, hashtags, and tone. Copy-to-clipboard for each platform. | | | |
| QC-055 | **Generate show notes and summary** | P3-AIG-03 | Should | QC-052 |
| | Add a "Show Notes" tab in the export view. Generate a structured summary with key takeaways, timestamps, and topic overview. Support markdown output. Copy-to-clipboard and optional .md file export. | | | |
| QC-056 | **Auto-generate chapter markers** | P3-AIG-04 | Should | QC-052, QC-013 |
| | Analyze transcript for topic changes and generate chapter markers with timestamps and titles. Display chapters on the video timeline. Include chapters in exported video metadata where format supports it. | | | |

### Brand Kit & Templates

| # | Ticket | PRD Ref | Priority | Dependencies |
|---|--------|---------|----------|--------------|
| QC-057 | **Add logo/watermark overlay** | P3-BRK-01 | Should | — |
| | Allow users to upload a logo image and position it on the video (corners or custom position). Set opacity and size. Apply as a `CALayer` in the export composition. Persist logo settings per project. | | | |
| QC-058 | **Add brand color palette for captions** | P3-BRK-03 | Should | QC-014, QC-016 |
| | Allow users to save a brand color palette (primary, secondary, accent, background). Apply brand colors to caption styles automatically. Persist palette in UserDefaults. | | | |
| QC-059 | **Save and reuse export presets** | P3-BRK-04 | Should | QC-014, QC-048 |
| | Allow users to save a combination of caption style + export format + aspect ratio + audio settings as a named preset. Load presets from a dropdown in the export view. Persist with SwiftData or UserDefaults. | | | |
| QC-060 | **Add intro/outro templates** | P3-BRK-02 | Could | QC-042 |
| | Allow users to upload or create short intro/outro clips. Automatically prepend/append them during export using `AVMutableComposition` track insertion. Support customizable text overlays on templates. | | | |

---

## Summary

| Phase | Tickets | Must | Should | Could |
|-------|---------|------|--------|-------|
| **Phase 1** — Foundation | QC-001 to QC-020 | 14 | 5 | 1 |
| **Phase 2** — Intelligence | QC-021 to QC-041 | 12 | 8 | 1 |
| **Phase 3** — Scale | QC-042 to QC-060 | 6 | 12 | 1 |
| **Total** | **60 tickets** | **32** | **25** | **3** |

### Recommended execution order within each phase

**Phase 1:** QC-001 → QC-007 → QC-002 → QC-003 → QC-013 → QC-014 → QC-015 → QC-016 → QC-017 → QC-018 → QC-008 → QC-009 → QC-010 → QC-012

**Phase 2:** QC-021 → QC-022 → QC-023 → QC-025 → QC-026 → QC-027 → QC-028 → QC-029 → QC-030 → QC-032 → QC-034 → QC-035 → QC-036 → QC-037 → QC-039

**Phase 3:** QC-042 → QC-043 → QC-044 → QC-046 → QC-047 → QC-048 → QC-052 → QC-053 → QC-054 → QC-057 → QC-058 → QC-059
