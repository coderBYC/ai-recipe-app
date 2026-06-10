import AVFoundation
import UIKit

/// Background frame capture for free-tier Smart Thumbnails (no Cloudinary bandwidth).
enum SmartThumbnailFrameExtractor {
    /// Captures one frame at `seconds` from a remote/local MP4 URL.
    static func captureFrame(videoURL: URL, seconds: Double) async throws -> UIImage {
        try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: videoURL)
            let (isPlayable, duration) = try await asset.load(.isPlayable, .duration)
            guard isPlayable else {
                throw NSError(
                    domain: "SmartThumbnailFrameExtractor",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Video is not playable at \(videoURL.absoluteString)"]
                )
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 300, height: 300)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

            let durationSeconds = duration.seconds
            let clamped = durationSeconds.isFinite && durationSeconds > 0
                ? min(max(0, seconds), max(0, durationSeconds - 0.05))
                : max(0, seconds)
            let time = CMTime(seconds: clamped, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        }.value
    }
}
