import AVFoundation
import AppKit
import QuartzCore

class ExportService {

    enum ExportError: LocalizedError {
        case noVideoTrack
        case noContentAfterDeletions
        case trackCreationFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "No video track found"
            case .noContentAfterDeletions: return "No video content remaining after deletions"
            case .trackCreationFailed: return "Failed to create video track"
            }
        }
    }

    struct CompositionResult {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
    }

    private func buildComposition(
        sourceURL: URL,
        captions: [TimedCaption],
        processedAudioURL: URL?,
        aspectRatio: AspectRatioOption,
        captionStyle: CaptionStyle,
        exclusionRanges: [CMTimeRange],
        includeAnimationTool: Bool = true
    ) async throws -> CompositionResult {
        let asset = AVAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let videoTrack = videoTracks.first else {
            throw ExportError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration)

        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.trackCreationFailed
        }

        let includedRanges = Self.computeIncludedRanges(
            fullDuration: duration,
            exclusionRanges: exclusionRanges
        )

        guard !includedRanges.isEmpty else {
            throw ExportError.noContentAfterDeletions
        }

        // Insert included segments into composition
        var insertionTime = CMTime.zero
        for range in includedRanges {
            try compositionVideoTrack.insertTimeRange(range, of: videoTrack, at: insertionTime)
            insertionTime = insertionTime + range.duration
        }

        let audioSource: AVAssetTrack?
        let audioAsset: AVAsset?
        if let processedAudioURL = processedAudioURL {
            let processed = AVURLAsset(url: processedAudioURL)
            let processedTracks = try await processed.loadTracks(withMediaType: .audio)
            audioSource = processedTracks.first
            audioAsset = processed
        } else {
            audioSource = audioTracks.first
            audioAsset = asset
        }

        if let audioTrackSource = audioSource,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            var audioInsertionTime = CMTime.zero
            if exclusionRanges.isEmpty {
                let audioDuration: CMTime
                if let audioAsset = audioAsset {
                    audioDuration = try await audioAsset.load(.duration)
                } else {
                    audioDuration = duration
                }
                let audioRange = CMTimeRange(start: .zero, duration: min(duration, audioDuration))
                try compositionAudioTrack.insertTimeRange(audioRange, of: audioTrackSource, at: .zero)
            } else {
                for range in includedRanges {
                    try compositionAudioTrack.insertTimeRange(range, of: audioTrackSource, at: audioInsertionTime)
                    audioInsertionTime = audioInsertionTime + range.duration
                }
            }
        }

        let compositionDuration = insertionTime

        let sourceWidth = naturalSize.width
        let sourceHeight = naturalSize.height
        let outputWidth = aspectRatio.outputSize.width
        let outputHeight = aspectRatio.outputSize.height

        let scaleX = outputWidth / sourceWidth
        let scaleY = outputHeight / sourceHeight
        let scale = max(scaleX, scaleY)
        let scaledWidth = sourceWidth * scale
        let scaledHeight = sourceHeight * scale
        let translateX = -(scaledWidth - outputWidth) / 2.0
        let translateY = -(scaledHeight - outputHeight) / 2.0

        var transform = CGAffineTransform.identity
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: translateX / scale, y: translateY / scale)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: outputWidth, height: outputHeight)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: compositionDuration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(transform, at: .zero)

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let adjustedCaptions = exclusionRanges.isEmpty
            ? captions
            : Self.adjustCaptions(captions, excludedRanges: exclusionRanges)

        if includeAnimationTool && !adjustedCaptions.isEmpty {
            let videoLayer = CALayer()
            videoLayer.frame = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)

            let parentLayer = CALayer()
            parentLayer.frame = videoLayer.frame
            parentLayer.addSublayer(videoLayer)

            let totalDuration = CMTimeGetSeconds(compositionDuration)
            let engine = CaptionStyleEngine()
            let captionLayers = engine.buildCaptionLayers(
                captions: adjustedCaptions,
                style: captionStyle,
                videoSize: CGSize(width: outputWidth, height: outputHeight),
                totalDuration: totalDuration
            )
            for layer in captionLayers {
                parentLayer.addSublayer(layer)
            }

            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )
        }

        return CompositionResult(composition: composition, videoComposition: videoComposition)
    }

    func buildPreviewPlayerItem(
        sourceURL: URL,
        captions: [TimedCaption],
        processedAudioURL: URL?,
        aspectRatio: AspectRatioOption,
        captionStyle: CaptionStyle,
        exclusionRanges: [CMTimeRange]
    ) async throws -> AVPlayerItem {
        let result = try await buildComposition(
            sourceURL: sourceURL,
            captions: captions,
            processedAudioURL: processedAudioURL,
            aspectRatio: aspectRatio,
            captionStyle: captionStyle,
            exclusionRanges: exclusionRanges,
            includeAnimationTool: false
        )
        let playerItem = AVPlayerItem(asset: result.composition)
        playerItem.videoComposition = result.videoComposition
        return playerItem
    }

    func exportToDownloads(
        sourceURL: URL,
        title: String,
        captions: [TimedCaption],
        processedAudioURL: URL? = nil,
        aspectRatio: AspectRatioOption = .vertical,
        captionStyle: CaptionStyle = .classic,
        exclusionRanges: [CMTimeRange] = [],
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            completion(false, "Could not access Downloads directory")
            return
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let sanitizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName: String
        if sanitizedTitle.isEmpty {
            fileName = "QuickCam_\(dateFormatter.string(from: Date())).mov"
        } else {
            fileName = "\(sanitizedTitle)_\(dateFormatter.string(from: Date())).mov"
        }
        let destinationURL = downloadsURL.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: destinationURL)

        Task {
            do {
                let result = try await buildComposition(
                    sourceURL: sourceURL,
                    captions: captions,
                    processedAudioURL: processedAudioURL,
                    aspectRatio: aspectRatio,
                    captionStyle: captionStyle,
                    exclusionRanges: exclusionRanges
                )

                guard let exportSession = AVAssetExportSession(
                    asset: result.composition,
                    presetName: AVAssetExportPresetHighestQuality
                ) else {
                    await MainActor.run {
                        completion(false, "Failed to create export session")
                    }
                    return
                }

                exportSession.outputURL = destinationURL
                exportSession.outputFileType = .mov
                exportSession.videoComposition = result.videoComposition

                await exportSession.export()

                switch exportSession.status {
                case .completed:
                    await MainActor.run {
                        completion(true, destinationURL.path)
                    }
                case .failed:
                    let errorMsg = exportSession.error?.localizedDescription ?? "Export failed"
                    await MainActor.run {
                        completion(false, errorMsg)
                    }
                case .cancelled:
                    await MainActor.run {
                        completion(false, "Export cancelled")
                    }
                default:
                    await MainActor.run {
                        completion(false, "Unknown export error")
                    }
                }

            } catch {
                await MainActor.run {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Screen + Camera Composition

    private func buildScreenCameraComposition(
        screenURL: URL,
        cameraURL: URL?,
        layout: ScreenCameraLayout,
        bubblePosition: CameraBubblePosition,
        captions: [TimedCaption],
        processedAudioURL: URL?,
        captionStyle: CaptionStyle,
        exclusionRanges: [CMTimeRange],
        includeAnimationTool: Bool = true
    ) async throws -> CompositionResult {
        let screenAsset = AVAsset(url: screenURL)
        let screenVideoTracks = try await screenAsset.loadTracks(withMediaType: .video)
        guard let screenVideoTrack = screenVideoTracks.first else {
            throw ExportError.noVideoTrack
        }
        let screenSize = try await screenVideoTrack.load(.naturalSize)
        let screenDuration = try await screenAsset.load(.duration)

        let composition = AVMutableComposition()

        // Output size: 1920x1080 (landscape for screen recording)
        let outputWidth: CGFloat = 1920
        let outputHeight: CGFloat = 1080

        // Screen track
        guard let compScreenTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: CMPersistentTrackID(1)
        ) else {
            throw ExportError.trackCreationFailed
        }

        let includedRanges = Self.computeIncludedRanges(
            fullDuration: screenDuration,
            exclusionRanges: exclusionRanges
        )
        guard !includedRanges.isEmpty else {
            throw ExportError.noContentAfterDeletions
        }

        var insertionTime = CMTime.zero
        for range in includedRanges {
            try compScreenTrack.insertTimeRange(range, of: screenVideoTrack, at: insertionTime)
            insertionTime = insertionTime + range.duration
        }

        let compositionDuration = insertionTime

        // Camera track (if available)
        var compCameraTrack: AVMutableCompositionTrack?
        if let cameraURL = cameraURL {
            let cameraAsset = AVAsset(url: cameraURL)
            let cameraVideoTracks = try await cameraAsset.loadTracks(withMediaType: .video)
            if let cameraVideoTrack = cameraVideoTracks.first {
                let track = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: CMPersistentTrackID(2)
                )
                if let track = track {
                    var camInsertionTime = CMTime.zero
                    for range in includedRanges {
                        let cameraDuration = try await cameraAsset.load(.duration)
                        let clampedRange = CMTimeRange(
                            start: range.start,
                            duration: min(range.duration, CMTimeSubtract(cameraDuration, range.start))
                        )
                        if CMTimeGetSeconds(clampedRange.duration) > 0 {
                            try track.insertTimeRange(clampedRange, of: cameraVideoTrack, at: camInsertionTime)
                        }
                        camInsertionTime = camInsertionTime + range.duration
                    }
                    compCameraTrack = track
                }
            }
        }

        // Audio track (from camera file which has mic audio, or screen file)
        let audioSourceURL = cameraURL ?? screenURL
        let audioAsset: AVAsset
        if let processedAudioURL = processedAudioURL {
            audioAsset = AVAsset(url: processedAudioURL)
        } else {
            audioAsset = AVAsset(url: audioSourceURL)
        }
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first,
           let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            var audioInsertionTime = CMTime.zero
            for range in includedRanges {
                let audioDuration = try await audioAsset.load(.duration)
                let clampedRange = CMTimeRange(
                    start: range.start,
                    duration: min(range.duration, CMTimeSubtract(audioDuration, range.start))
                )
                if CMTimeGetSeconds(clampedRange.duration) > 0 {
                    try compAudioTrack.insertTimeRange(clampedRange, of: audioTrack, at: audioInsertionTime)
                }
                audioInsertionTime = audioInsertionTime + range.duration
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: outputWidth, height: outputHeight)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        if layout == .sideBySide {
            // Side by side: standard layer instructions
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: compositionDuration)

            // Screen on left half
            let screenLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compScreenTrack)
            let screenScaleX = (outputWidth / 2) / screenSize.width
            let screenScaleY = outputHeight / screenSize.height
            let screenScale = max(screenScaleX, screenScaleY)
            let screenScaledW = screenSize.width * screenScale
            let screenScaledH = screenSize.height * screenScale
            var screenTransform = CGAffineTransform.identity
            screenTransform = screenTransform.scaledBy(x: screenScale, y: screenScale)
            screenTransform = screenTransform.translatedBy(
                x: ((outputWidth / 2) - screenScaledW) / (2 * screenScale),
                y: (outputHeight - screenScaledH) / (2 * screenScale)
            )
            screenLayerInstruction.setTransform(screenTransform, at: .zero)

            var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []

            if let compCameraTrack = compCameraTrack {
                let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compCameraTrack)
                // Camera on right half - need camera natural size
                let cameraAsset = AVAsset(url: cameraURL!)
                let cameraTracks = try await cameraAsset.loadTracks(withMediaType: .video)
                let camSize = try await cameraTracks.first!.load(.naturalSize)
                let camScaleX = (outputWidth / 2) / camSize.width
                let camScaleY = outputHeight / camSize.height
                let camScale = max(camScaleX, camScaleY)
                let camScaledW = camSize.width * camScale
                let camScaledH = camSize.height * camScale
                var camTransform = CGAffineTransform.identity
                camTransform = camTransform.translatedBy(x: outputWidth / 2, y: 0)
                camTransform = camTransform.scaledBy(x: camScale, y: camScale)
                camTransform = camTransform.translatedBy(
                    x: ((outputWidth / 2) - camScaledW) / (2 * camScale),
                    y: (outputHeight - camScaledH) / (2 * camScale)
                )
                cameraLayerInstruction.setTransform(camTransform, at: .zero)
                layerInstructions.append(cameraLayerInstruction)
            }

            layerInstructions.append(screenLayerInstruction)
            instruction.layerInstructions = layerInstructions
            videoComposition.instructions = [instruction]
        } else {
            // Bubble layouts: use custom compositor
            let customInstruction = ScreenCameraCompositionInstruction(
                timeRange: CMTimeRange(start: .zero, duration: compositionDuration),
                screenTrackID: compScreenTrack.trackID,
                cameraTrackID: compCameraTrack?.trackID ?? kCMPersistentTrackID_Invalid,
                layout: layout,
                bubblePosition: bubblePosition,
                outputSize: CGSize(width: outputWidth, height: outputHeight)
            )
            videoComposition.instructions = [customInstruction]
            videoComposition.customVideoCompositorClass = ScreenCameraCompositor.self
        }

        // Add captions
        let adjustedCaptions = exclusionRanges.isEmpty
            ? captions
            : Self.adjustCaptions(captions, excludedRanges: exclusionRanges)

        if includeAnimationTool && !adjustedCaptions.isEmpty && layout == .sideBySide {
            let videoLayer = CALayer()
            videoLayer.frame = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)

            let parentLayer = CALayer()
            parentLayer.frame = videoLayer.frame
            parentLayer.addSublayer(videoLayer)

            let totalDuration = CMTimeGetSeconds(compositionDuration)
            let engine = CaptionStyleEngine()
            let captionLayers = engine.buildCaptionLayers(
                captions: adjustedCaptions,
                style: captionStyle,
                videoSize: CGSize(width: outputWidth, height: outputHeight),
                totalDuration: totalDuration
            )
            for layer in captionLayers {
                parentLayer.addSublayer(layer)
            }

            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )
        }

        return CompositionResult(composition: composition, videoComposition: videoComposition)
    }

    func buildScreenCameraPreviewPlayerItem(
        screenURL: URL,
        cameraURL: URL?,
        layout: ScreenCameraLayout,
        bubblePosition: CameraBubblePosition,
        captions: [TimedCaption],
        processedAudioURL: URL?,
        captionStyle: CaptionStyle,
        exclusionRanges: [CMTimeRange]
    ) async throws -> AVPlayerItem {
        let result = try await buildScreenCameraComposition(
            screenURL: screenURL,
            cameraURL: cameraURL,
            layout: layout,
            bubblePosition: bubblePosition,
            captions: captions,
            processedAudioURL: processedAudioURL,
            captionStyle: captionStyle,
            exclusionRanges: exclusionRanges,
            includeAnimationTool: false
        )
        let playerItem = AVPlayerItem(asset: result.composition)
        playerItem.videoComposition = result.videoComposition
        return playerItem
    }

    func exportScreenCameraComposition(
        screenURL: URL,
        cameraURL: URL?,
        layout: ScreenCameraLayout,
        bubblePosition: CameraBubblePosition,
        captions: [TimedCaption],
        captionStyle: CaptionStyle,
        processedAudioURL: URL?,
        exclusionRanges: [CMTimeRange],
        title: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            completion(false, "Could not access Downloads directory")
            return
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let sanitizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName: String
        if sanitizedTitle.isEmpty {
            fileName = "QuickCam_\(dateFormatter.string(from: Date())).mov"
        } else {
            fileName = "\(sanitizedTitle)_\(dateFormatter.string(from: Date())).mov"
        }
        let destinationURL = downloadsURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destinationURL)

        Task {
            do {
                let result = try await buildScreenCameraComposition(
                    screenURL: screenURL,
                    cameraURL: cameraURL,
                    layout: layout,
                    bubblePosition: bubblePosition,
                    captions: captions,
                    processedAudioURL: processedAudioURL,
                    captionStyle: captionStyle,
                    exclusionRanges: exclusionRanges
                )

                guard let exportSession = AVAssetExportSession(
                    asset: result.composition,
                    presetName: AVAssetExportPresetHighestQuality
                ) else {
                    await MainActor.run {
                        completion(false, "Failed to create export session")
                    }
                    return
                }

                exportSession.outputURL = destinationURL
                exportSession.outputFileType = .mov
                exportSession.videoComposition = result.videoComposition

                await exportSession.export()

                switch exportSession.status {
                case .completed:
                    await MainActor.run {
                        completion(true, destinationURL.path)
                    }
                case .failed:
                    let errorMsg = exportSession.error?.localizedDescription ?? "Export failed"
                    await MainActor.run {
                        completion(false, errorMsg)
                    }
                case .cancelled:
                    await MainActor.run {
                        completion(false, "Export cancelled")
                    }
                default:
                    await MainActor.run {
                        completion(false, "Unknown export error")
                    }
                }

            } catch {
                await MainActor.run {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Exclusion Range Helpers

    static func computeIncludedRanges(fullDuration: CMTime, exclusionRanges: [CMTimeRange]) -> [CMTimeRange] {
        guard !exclusionRanges.isEmpty else {
            return [CMTimeRange(start: .zero, duration: fullDuration)]
        }

        let sorted = exclusionRanges.sorted { CMTimeCompare($0.start, $1.start) < 0 }

        // Merge overlapping ranges
        var merged: [CMTimeRange] = []
        for range in sorted {
            if let last = merged.last, CMTimeRangeContainsTime(last, time: range.start) || CMTimeCompare(last.end, range.start) >= 0 {
                let newEnd = max(CMTimeGetSeconds(last.end), CMTimeGetSeconds(range.end))
                merged[merged.count - 1] = CMTimeRange(
                    start: last.start,
                    end: CMTime(seconds: newEnd, preferredTimescale: 600)
                )
            } else {
                merged.append(range)
            }
        }

        // Compute complement
        var included: [CMTimeRange] = []
        var cursor = CMTime.zero
        for range in merged {
            if CMTimeCompare(cursor, range.start) < 0 {
                included.append(CMTimeRange(start: cursor, end: range.start))
            }
            cursor = range.end
        }
        if CMTimeCompare(cursor, fullDuration) < 0 {
            included.append(CMTimeRange(start: cursor, end: fullDuration))
        }

        return included
    }

    static func adjustCaptions(_ captions: [TimedCaption], excludedRanges: [CMTimeRange]) -> [TimedCaption] {
        let sorted = excludedRanges.sorted { CMTimeCompare($0.start, $1.start) < 0 }

        func adjustTime(_ time: CMTime) -> CMTime {
            var offset = CMTime.zero
            for range in sorted {
                if CMTimeCompare(time, range.start) <= 0 { break }
                if CMTimeCompare(time, range.end) >= 0 {
                    offset = offset + range.duration
                } else {
                    offset = offset + CMTimeSubtract(time, range.start)
                }
            }
            return CMTimeSubtract(time, offset)
        }

        func isExcluded(_ time: CMTime) -> Bool {
            sorted.contains { CMTimeRangeContainsTime($0, time: time) }
        }

        var result: [TimedCaption] = []
        for caption in captions {
            let adjustedWords = caption.words.compactMap { word -> TimedWord? in
                guard !isExcluded(word.startTime) else { return nil }
                return TimedWord(
                    text: word.text,
                    startTime: adjustTime(word.startTime),
                    endTime: adjustTime(word.endTime)
                )
            }
            guard let firstWord = adjustedWords.first,
                  let lastWord = adjustedWords.last else { continue }
            let adjustedCaption = TimedCaption(
                text: adjustedWords.map { $0.text }.joined(separator: " "),
                startTime: firstWord.startTime,
                endTime: lastWord.endTime,
                words: adjustedWords
            )
            result.append(adjustedCaption)
        }
        return result
    }
}
