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

                let timeRange = CMTimeRange(start: .zero, duration: duration)
                try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

                if let processedAudioURL = processedAudioURL {
                    let processedAsset = AVURLAsset(url: processedAudioURL)
                    let processedAudioTracks = try await processedAsset.loadTracks(withMediaType: .audio)
                    if let processedAudioTrack = processedAudioTracks.first,
                       let compositionAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                       ) {
                        let processedDuration = try await processedAsset.load(.duration)
                        let processedTimeRange = CMTimeRange(start: .zero, duration: min(duration, processedDuration))
                        try compositionAudioTrack.insertTimeRange(processedTimeRange, of: processedAudioTrack, at: .zero)
                    }
                } else if let audioTrack = audioTracks.first {
                    if let compositionAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) {
                        try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
                    }
                }

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
                instruction.timeRange = timeRange

                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
                layerInstruction.setTransform(transform, at: .zero)

                instruction.layerInstructions = [layerInstruction]
                videoComposition.instructions = [instruction]

                if !captions.isEmpty {
                    let videoLayer = CALayer()
                    videoLayer.frame = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)

                    let parentLayer = CALayer()
                    parentLayer.frame = videoLayer.frame
                    parentLayer.addSublayer(videoLayer)

                    let totalDuration = CMTimeGetSeconds(duration)
                    let engine = CaptionStyleEngine()
                    let captionLayers = engine.buildCaptionLayers(
                        captions: captions,
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
}
