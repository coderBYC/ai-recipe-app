import Foundation
import SwiftData

enum RecipeSource: String, Codable, CaseIterable, Identifiable {
    case youtube = "YouTube"
    case instagram = "Instagram"
    case tiktok = "TikTok"
    /// Saved video from the user’s photo library (e.g. downloaded from another app).
    case photos = "Photos"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .instagram: return "camera.fill"
        case .tiktok: return "music.note"
        case .photos: return "photo.on.rectangle.angled"
        }
    }
    
    /// Asset name in Assets.xcassets for real brand icon (InstagramIcon, YouTubeIcon, TikTokIcon).
    var iconAssetName: String? {
        switch self {
        case .youtube: return "YouTubeIcon"
        case .instagram: return "InstagramIcon"
        case .tiktok: return "TikTokIcon"
        case .photos: return nil
        }
    }
    
    static func inferred(from urlString: String) -> RecipeSource {
        let lower = urlString.lowercased()
        if lower.hasPrefix("photos://") { return .photos }
        if lower.contains("instagram") { return .instagram }
        if lower.contains("tiktok") { return .tiktok }
        if lower.contains("youtube") || lower.contains("youtu.be") { return .youtube }
        return .youtube
    }
}

@Model
final class Recipe: Identifiable {
    @Attribute(.unique) var id: String
    /// Supabase Auth user id (`uuidString`) who owns this row locally; scopes Home / sync per account.
    var ownerUserId: String
    var title: String
    var source: String
    var sourceURL: String
    var creator: String
    var timestamp: String
    var ingredients: String
    var estimatedCookingMinutes: Int
    var prepMinutes: Int
    var totalSteps: Int
    var triedBefore: Bool
    var notes: String
    var createdAt: Date
    /// Bumped on every user-visible edit; drives incremental cloud sync.
    var updatedAt: Date
    /// When set, the recipe is treated as removed from Home (soft delete).
    var deletedAt: Date?
    /// 0–5 star rating given by the user.
    var rating: Int
    /// URL to the downloaded video (served by backend) for in-app playback. Empty for YouTube (use sourceURL embed instead).
    var downloadedVideoURL: String
    /// Seconds from video start where the finished dish is clearest (from analyze JSON); used with AVAssetImageGenerator for IG/TikTok preview.
    var dishHeroTimestampSeconds: Double
    /// Newline-separated step descriptions for circle-line timeline.
    var stepsContent: String
    /// Comma-separated "1" or "0" for each ingredient line (checked or not).
    var ingredientCheckmarks: String

    /// Recipes created in the pre-auth onboarding chrome use this so they never mix with a signed-in user’s library.
    static let localOnboardingOwnerPlaceholder = "__onboarding_local__"

    private static let ownerMigrationDefaultsKey = "recipeOwnerUserIdMigration_v1"

    init(
        id: String = "",
        ownerUserId: String = "",
        title: String = "",
        source: RecipeSource = .youtube,
        sourceURL: String = "",
        creator: String = "",
        timestamp: String = "",
        ingredients: String = "",
        estimatedCookingMinutes: Int = 0,
        prepMinutes: Int = 0,
        totalSteps: Int = 0,
        triedBefore: Bool = false,
        notes: String = "",
        stepsContent: String = "",
        ingredientCheckmarks: String = "",
        downloadedVideoURL: String = "",
        dishHeroTimestampSeconds: Double = 1,
        rating: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = trimmedId.isEmpty ? UUID().uuidString : trimmedId
        self.ownerUserId = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title
        self.source = source.rawValue
        self.sourceURL = sourceURL
        self.creator = creator
        self.timestamp = timestamp
        self.ingredients = ingredients
        self.estimatedCookingMinutes = estimatedCookingMinutes
        self.prepMinutes = prepMinutes
        self.totalSteps = totalSteps
        self.triedBefore = triedBefore
        self.notes = notes
        self.downloadedVideoURL = downloadedVideoURL
        self.dishHeroTimestampSeconds = dishHeroTimestampSeconds
        self.stepsContent = stepsContent
        self.ingredientCheckmarks = ingredientCheckmarks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.rating = rating
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

    /// Plain-text representation for export/share; counts as one export when shared.
    var shareableExportText: String {
        var lines: [String] = []
        lines.append(title.isEmpty ? "Recipe" : title)
        if !creator.isEmpty { lines.append("By \(creator)") }
        lines.append("Time: \(estimatedCookingMinutes) min")
        lines.append("")
        lines.append("Ingredients:")
        for line in ingredientLines { lines.append("• \(line)") }
        lines.append("")
        lines.append("Steps:")
        for (i, step) in stepLines.enumerated() { lines.append("\(i + 1). \(step)") }
        if !sourceURL.isEmpty { lines.append(""); lines.append("Source: \(sourceURL)") }
        return lines.joined(separator: "\n")
    }

    /// One-time: legacy rows had no owner; assign them to the first signed-in user on this install so lists stay consistent.
    @MainActor
    static func migrateUnassignedOwnersOnce(modelContext: ModelContext, assignedTo: String) {
        guard !assignedTo.isEmpty else { return }
        guard !UserDefaults.standard.bool(forKey: ownerMigrationDefaultsKey) else { return }
        let desc = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.ownerUserId == "" })
        guard let rows = try? modelContext.fetch(desc) else {
            UserDefaults.standard.set(true, forKey: ownerMigrationDefaultsKey)
            return
        }
        for r in rows { r.ownerUserId = assignedTo }
        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: ownerMigrationDefaultsKey)
    }
}
