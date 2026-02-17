import AVFoundation
import AppKit

class RecordingsRepository {
    func loadPreviousRecordings() -> [RecordedVideo] {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return []
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: downloadsURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: .skipsHiddenFiles
            )

            let videoFiles = files.filter { url in
                let filename = url.lastPathComponent
                let isMov = url.pathExtension.lowercased() == "mov"
                let isQuickCam = filename.hasPrefix("QuickCam_") || filename.contains("QuickCam")
                let hasDatePattern = filename.range(of: "_\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil
                return isMov && (isQuickCam || hasDatePattern)
            }

            var recordings: [RecordedVideo] = []

            for url in videoFiles {
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let date = (attributes?[.modificationDate] as? Date) ?? Date()

                var title = url.deletingPathExtension().lastPathComponent
                if let range = title.range(of: "_\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}-\\d{2}$", options: .regularExpression) {
                    title = String(title[..<range.lowerBound])
                }
                if title == "QuickCam" {
                    title = "Untitled"
                }

                let thumbnail = generateThumbnail(for: url)

                recordings.append(RecordedVideo(
                    url: url,
                    thumbnail: thumbnail,
                    date: date,
                    title: title
                ))
            }

            recordings.sort { $0.date > $1.date }
            return recordings
        } catch {
            return []
        }
    }

    func generateThumbnail(for url: URL) -> NSImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 200, height: 200)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            return nil
        }
    }

    func deleteRecording(_ video: RecordedVideo) {
        try? FileManager.default.removeItem(at: video.url)
    }

    func discardRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
