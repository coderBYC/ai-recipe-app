import Foundation
import SwiftData

enum RecipeSource: String, Codable, CaseIterable, Identifiable {
    case youtube = "YouTube"
    case instagram = "Instagram"
    case tiktok = "TikTok"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .instagram: return "camera.fill"
        case .tiktok: return "music.note"
        }
    }
    
    /// Asset name in Assets.xcassets for real brand icon (InstagramIcon, YouTubeIcon, TikTokIcon).
    var iconAssetName: String? {
        switch self {
        case .youtube: return "YouTubeIcon"
        case .instagram: return "InstagramIcon"
        case .tiktok: return "TikTokIcon"
        }
    }
    
    static func inferred(from urlString: String) -> RecipeSource {
        let lower = urlString.lowercased()
        if lower.contains("instagram") { return .instagram }
        if lower.contains("tiktok") { return .tiktok }
        if lower.contains("youtube") || lower.contains("youtu.be") { return .youtube }
        return .youtube
    }
}

@Model
final class Recipe: Identifiable {
    var id: UUID
    var title: String
    var source: String
    var sourceURL: String
    var creator: String
    var timestamp: String
    var ingredients: String
    var estimatedCookingMinutes: Int
    var totalSteps: Int
    var triedBefore: Bool
    var notes: String
    var customImageData: Data?
    var createdAt: Date
    /// URL to the downloaded video (served by backend) for in-app playback. Empty for YouTube (use sourceURL embed instead).
    var downloadedVideoURL: String
    /// Newline-separated step descriptions for circle-line timeline.
    var stepsContent: String
    /// Comma-separated "1" or "0" for each ingredient line (checked or not).
    var ingredientCheckmarks: String
    
    init(
        title: String = "",
        source: RecipeSource = .youtube,
        sourceURL: String = "",
        creator: String = "",
        timestamp: String = "",
        ingredients: String = "",
        estimatedCookingMinutes: Int = 0,
        totalSteps: Int = 0,
        triedBefore: Bool = false,
        notes: String = "",
        customImageData: Data? = nil,
        stepsContent: String = "",
        ingredientCheckmarks: String = "",
        downloadedVideoURL: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.source = source.rawValue
        self.sourceURL = sourceURL
        self.creator = creator
        self.timestamp = timestamp
        self.ingredients = ingredients
        self.estimatedCookingMinutes = estimatedCookingMinutes
        self.totalSteps = totalSteps
        self.triedBefore = triedBefore
        self.notes = notes
        self.customImageData = customImageData
        self.downloadedVideoURL = downloadedVideoURL
        self.stepsContent = stepsContent
        self.ingredientCheckmarks = ingredientCheckmarks
        self.createdAt = Date()
    }
    
    var sourceEnum: RecipeSource {
        get { RecipeSource(rawValue: source) ?? .youtube }
        set { source = newValue.rawValue }
    }
    
    static func youtubeThumbnailURL(from urlString: String) -> URL? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              url.host?.contains("youtube") == true || url.host == "youtu.be"
        else { return nil }
        var videoId: String?
        if url.path.hasPrefix("/shorts/") {
            videoId = url.path.replacingOccurrences(of: "/shorts/", with: "").split(separator: "/").first.map(String.init)
        } else if url.host == "youtu.be" {
            videoId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "?").first.map(String.init)
        } else if let comp = URLComponents(url: url, resolvingAgainstBaseURL: false), let v = comp.queryItems?.first(where: { $0.name == "v" })?.value {
            videoId = v
        }
        guard let id = videoId, !id.isEmpty else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(id)/mqdefault.jpg")
    }

    /// Embed URL for in-app YouTube playback (e.g. https://www.youtube.com/embed/VIDEO_ID).
    static func youtubeEmbedURL(from urlString: String) -> URL? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              url.host?.contains("youtube") == true || url.host == "youtu.be"
        else { return nil }
        var videoId: String?
        if url.path.hasPrefix("/shorts/") {
            videoId = url.path.replacingOccurrences(of: "/shorts/", with: "").split(separator: "/").first.map(String.init)
        } else if url.host == "youtu.be" {
            videoId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "?").first.map(String.init)
        } else if let comp = URLComponents(url: url, resolvingAgainstBaseURL: false), let v = comp.queryItems?.first(where: { $0.name == "v" })?.value {
            videoId = v
        }
        guard let id = videoId, !id.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1")
    }
    
    /// Ingredient lines (trimmed, non-empty).
    var ingredientLines: [String] {
        ingredients.split(separator: "\n", omittingEmptySubsequences: true).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    
    /// Step lines from stepsContent.
    var stepLines: [String] {
        stepsContent.split(separator: "\n", omittingEmptySubsequences: true).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    
    /// Parsed checkmarks for ingredients (same count as ingredientLines; default false).
    func ingredientChecked(at index: Int) -> Bool {
        let parts = ingredientCheckmarks.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard index >= 0, index < parts.count else { return false }
        return parts[index].trimmingCharacters(in: .whitespaces) == "1"
    }
}
