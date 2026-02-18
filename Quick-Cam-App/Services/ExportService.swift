import AVFoundation
import AppKit
import QuartzCore

class ExportService {
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

        let asset = AVAsset(url: sourceURL)

        Task {
            do {
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)

                guard let videoTrack = videoTracks.first else {
                    await MainActor.run {
                        completion(false, "No video track found")
                    }
                    return
                }

                let naturalSize = try await videoTrack.load(.naturalSize)
                let duration = try await asset.load(.duration)

                let composition = AVMutableComposition()

                guard let compositionVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    await MainActor.run {
                        completion(false, "Failed to create video track")
                    }
                    return
                }

                let includedRanges = Self.computeIncludedRanges(
                    fullDuration: duration,
                    exclusionRanges: exclusionRanges
                )

                guard !includedRanges.isEmpty else {
                    await MainActor.run {
                        completion(false, "No video content remaining after deletions")
                    }
                    return
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
                        // No exclusions: insert full range
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

                if !adjustedCaptions.isEmpty {
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

                guard let exportSession = AVAssetExportSession(
                    asset: composition,
                    presetName: AVAssetExportPresetHighestQuality
                ) else {
                    await MainActor.run {
                        completion(false, "Failed to create export session")
                    }
                    return
                }

                exportSession.outputURL = destinationURL
                exportSession.outputFileType = .mov
                exportSession.videoComposition = videoComposition

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
