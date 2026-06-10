import Foundation

/// Cook Mode list thumbnail payload (aligned with Supabase / backend analyze response).
struct SmartThumbnailAsset: Identifiable, Equatable, Hashable {
    /// Unique id for Kingfisher disk cache key (typically recipe id or thumbnail uuid).
    let thumbId: String
    /// MP4 playback URL used by free-tier on-device frame capture.
    let videoUrlString: String
    /// Exact frame time in seconds (e.g. dish hero timestamp).
    let timestampSeconds: Double
    /// Cloudinary CDN image URL for premium users (nil for free-only rows).
    let premiumCloudinaryUrl: String?

    var id: String { thumbId }

    init(
        thumbId: String,
        videoUrlString: String,
        timestampSeconds: Double,
        premiumCloudinaryUrl: String? = nil
    ) {
        self.thumbId = thumbId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.videoUrlString = videoUrlString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timestampSeconds = timestampSeconds
        let cloud = premiumCloudinaryUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.premiumCloudinaryUrl = (cloud?.isEmpty == false) ? cloud : nil
    }
}

enum SmartThumbnailMode {
    /// Home / Imports list: premium may load one Cloudinary dish-hero image.
    case listHero
    /// Cook Mode slideshow: each step uses AI `timestamp_seconds` + unique cache key.
    case cookModeStep(Int)
}

// MARK: - Recipe mapping

extension SmartThumbnailAsset {
    /// Home list hero thumbnail (Cloudinary for premium when available).
    init(recipe: Recipe) {
        self.init(recipe: recipe, mode: .listHero)
    }

    init(recipe: Recipe, mode: SmartThumbnailMode) {
        switch mode {
        case .listHero:
            thumbId = recipe.id
            timestampSeconds = recipe.dishHeroTimestampSeconds > 0 ? recipe.dishHeroTimestampSeconds : 1
        case .cookModeStep(let stepIndex):
            thumbId = "\(recipe.id)-step-\(stepIndex)"
            timestampSeconds = recipe.stepTimestampSeconds(at: stepIndex)
        }

        videoUrlString = recipe.resolvedVideoPlaybackURLString
        premiumCloudinaryUrl = recipe.premiumCloudinaryURLString
    }
}

// MARK: - Cloudinary resize helper

enum SmartThumbnailCloudinary {
    /// Injects `w_300,h_300,c_fill` after `/upload/` to keep disk cache small.
    static func resizedURL(from raw: String, width: Int = 300, height: Int = 300) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let marker = "/upload/"
        guard let range = trimmed.range(of: marker, options: .caseInsensitive) else {
            return URL(string: trimmed)
        }

        let transform = "w_\(width),h_\(height),c_fill"
        let suffix = String(trimmed[range.upperBound...])
        if suffix.hasPrefix("\(transform)/") {
            return URL(string: trimmed)
        }

        let prefix = String(trimmed[..<range.upperBound])
        return URL(string: prefix + transform + "/" + suffix)
    }
}
