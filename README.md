# 📸 Quick Cam

A lightweight macOS app for recording vertical videos (9:16 aspect ratio) optimized for social media platforms like Instagram, TikTok, and YouTube Shorts.

## ✨ Features

- **Vertical Video Recording** - Automatically crops and exports videos in 9:16 format
- **Multi-Camera Support** - Switch between built-in and external cameras
- **Auto-Generated Captions** - Uses speech recognition to add timed subtitles
- **Previous Recordings** - Browse and replay your recorded videos
- **High Quality Export** - Records at up to 4K resolution (2160×3840)
- **Simple Interface** - Clean, intuitive SwiftUI design

## 🖥️ Requirements

- macOS 14.0 (Sonoma) or later
- Camera access permission
- Microphone access permission (for audio recording)
- Speech recognition permission (for auto-captions)

## 🚀 Getting Started

### Building from Source

1. Clone this repository:
```bash
git clone <repository-url>
cd Quick-Cam-App
```

2. Open the project in Xcode:
```bash
open Quick-Cam-App.xcodeproj
```

3. Build and run (⌘R)

### First Launch

On first launch, Quick Cam will request the following permissions:
- **Camera** - Required for video recording
- **Microphone** - Required for audio recording
- **Speech Recognition** - Optional, needed only for auto-caption feature

## 📖 How to Use

1. **Select Camera** - Choose your camera from the dropdown (if multiple available)
2. **Start Recording** - Click the red record button
3. **Stop Recording** - Click the square stop button
4. **Preview** - Review your video, add a title, and optionally enable captions
5. **Save** - Export to your Downloads folder or retake

### Auto-Generated Captions

Toggle "Auto-generate captions" in the preview screen to:
- Transcribe speech using Apple's Speech Recognition
- Add timed subtitles burned into the video
- Captions appear at the bottom of the frame

## 📁 Project Structure

```
Quick-Cam-App/
├── Quick-Cam-App/
│   ├── Quick_Cam_AppApp.swift      # App entry point
│   ├── ContentView.swift           # Main UI (camera, sidebar, navigation)
│   ├── CameraManager.swift         # Core camera & video processing logic
│   ├── PreviewView.swift           # Post-recording preview screen
│   ├── Info.plist                  # App metadata & permissions
│   ├── Quick_Cam_App.entitlements  # Sandbox permissions
│   └── Assets.xcassets/            # App icons & colors
└── Quick-Cam-App.xcodeproj/        # Xcode project
```

## 🛠️ Technical Details

### Technology Stack
- **Language**: Swift
- **UI Framework**: SwiftUI
- **Key Frameworks**:
  - AVFoundation (camera & video)
  - AVKit (playback)
  - Speech (transcription)
  - Combine (reactive state)

### Video Processing Pipeline
1. Records horizontal video at highest available quality
2. During export, crops center portion to 9:16 vertical format (2160×3840)
3. Optionally transcribes audio and adds caption layers
4. Exports as `.mov` to Downloads folder

### Architecture Highlights
- **MVVM Pattern** - `CameraManager` as observable view model
- **Async/Await** - Modern Swift concurrency for video export
- **Background Processing** - Camera operations on dedicated queue
- **SwiftUI + AppKit Bridge** - `NSViewRepresentable` for AVFoundation views

## 🎯 Roadmap

Potential future improvements:
- [ ] Custom export location picker
- [ ] Multiple aspect ratio options (1:1, 16:9, 4:5)
- [ ] Video trimming and editing
- [ ] Custom caption styling
- [ ] Cloud upload integration
- [ ] Batch export

## 📝 License

[Add your license here]

## 👤 Author

[Add your information here]

## 🙏 Acknowledgments

Built with SwiftUI and AVFoundation
