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
    /// Local cookbook grouping on Home (`Cookbook.id`).
    var cookbookId: String
    var title: String
    var source: String
    var sourceURL: String
    var creator: String
    var timestamp: String
    var ingredients: String
    /// Recipe yield in servings (from AI or user edit); ingredient amounts are written for this count.
    var estimatedServings: Int
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
    /// Thumbnail / Cloudinary image URL for list & premium Cook Mode frames.
    var downloadedVideoURL: String
    /// MP4 playback URL for free-tier on-device frame capture (from analyze `video_url`).
    var videoPlaybackURL: String
    /// Comma-separated seconds per step, aligned with `stepLines` (from AI `instructions[].timestamp_seconds`).
    var stepTimestampsContent: String
    /// Seconds from video start where the finished dish is clearest (from analyze JSON).
    var dishHeroTimestampSeconds: Double
    /// Newline-separated step descriptions for circle-line timeline.
    var stepsContent: String
    /// Comma-separated "1" or "0" for each ingredient line (checked or not).
    var ingredientCheckmarks: String
    /// Saved to the Bookmarks sheet on Home.
    var isBookmarked: Bool
    /// Per-serving nutrition (Pro AI); 0 = unset.
    var nutritionCalories: Int
    var nutritionProteinGrams: Int
    var nutritionCarbsGrams: Int
    var nutritionFatGrams: Int

    /// Recipes created in the pre-auth onboarding chrome use this so they never mix with a signed-in user’s library.
    static let localOnboardingOwnerPlaceholder = "__onboarding_local__"

    private static let ownerMigrationDefaultsKey = "recipeOwnerUserIdMigration_v1"
    private static let servingsMigrationDefaultsKey = "recipeEstimatedServingsMigration_v1"

    init(
        id: String = "",
        ownerUserId: String = "",
        cookbookId: String = "",
        title: String = "",
        source: RecipeSource = .youtube,
        sourceURL: String = "",
        creator: String = "",
        timestamp: String = "",
        ingredients: String = "",
        estimatedServings: Int = 1,
        estimatedCookingMinutes: Int = 0,
        prepMinutes: Int = 0,
        totalSteps: Int = 0,
        triedBefore: Bool = false,
        notes: String = "",
        stepsContent: String = "",
        ingredientCheckmarks: String = "",
        downloadedVideoURL: String = "",
        videoPlaybackURL: String = "",
        stepTimestampsContent: String = "",
        dishHeroTimestampSeconds: Double = 1,
        rating: Int = 0,
        isBookmarked: Bool = false,
        nutritionCalories: Int = 0,
        nutritionProteinGrams: Int = 0,
        nutritionCarbsGrams: Int = 0,
        nutritionFatGrams: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = trimmedId.isEmpty ? UUID().uuidString : trimmedId
        self.ownerUserId = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cookbookId = cookbookId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title
        self.source = source.rawValue
        self.sourceURL = sourceURL
        self.creator = creator
        self.timestamp = timestamp
        self.ingredients = ingredients
        self.estimatedServings = max(1, estimatedServings)
        self.estimatedCookingMinutes = estimatedCookingMinutes
        self.prepMinutes = prepMinutes
        self.totalSteps = totalSteps
        self.triedBefore = triedBefore
        self.notes = notes
        self.downloadedVideoURL = downloadedVideoURL
        self.videoPlaybackURL = videoPlaybackURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.stepTimestampsContent = stepTimestampsContent.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dishHeroTimestampSeconds = dishHeroTimestampSeconds
        self.stepsContent = stepsContent
        self.ingredientCheckmarks = ingredientCheckmarks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.rating = rating
        self.isBookmarked = isBookmarked
        self.nutritionCalories = max(0, nutritionCalories)
        self.nutritionProteinGrams = max(0, nutritionProteinGrams)
        self.nutritionCarbsGrams = max(0, nutritionCarbsGrams)
        self.nutritionFatGrams = max(0, nutritionFatGrams)
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

    /// Parsed per-step video timestamps from AI (`stepTimestampsContent`).
    var stepTimestampValues: [Double] {
        stepTimestampsContent
            .split(separator: ",", omittingEmptySubsequences: false)
            .compactMap { part in
                let s = part.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                guard let v = Double(s), v >= 0, v.isFinite else { return nil }
                return v
            }
    }

    /// Video time in seconds for Cook Mode step `index` (AI timestamp, with legacy fallback).
    func stepTimestampSeconds(at index: Int) -> Double {
        let values = stepTimestampValues
        if index >= 0, index < values.count {
            return values[index]
        }
        let count = max(stepLines.count, 1)
        let hero = max(dishHeroTimestampSeconds, 1)
        if count <= 1 { return hero }
        return hero * Double(index) / Double(count - 1)
    }

    /// Resolved MP4 URL for AVAssetImageGenerator (free tier).
    var resolvedVideoPlaybackURLString: String {
        let video = videoPlaybackURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !video.isEmpty {
            return RecipeBackendConfig.resolvedMediaURL(video)?.absoluteString ?? video
        }
        let stored = downloadedVideoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stored.isEmpty, !stored.lowercased().contains("cloudinary.com") else { return "" }
        return RecipeBackendConfig.resolvedMediaURL(stored)?.absoluteString ?? stored
    }

    /// Cloudinary thumbnail URL when present (premium Cook Mode / list).
    var premiumCloudinaryURLString: String? {
        let thumb = downloadedVideoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard thumb.lowercased().contains("cloudinary.com") else { return nil }
        return RecipeBackendConfig.resolvedMediaURL(thumb)?.absoluteString ?? thumb
    }
    
    /// Parsed checkmarks for ingredients (same count as ingredientLines; default false).
    func ingredientChecked(at index: Int) -> Bool {
        let parts = ingredientCheckmarks.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard index >= 0, index < parts.count else { return false }
        return parts[index].trimmingCharacters(in: .whitespaces) == "1"
    }

    func setIngredientChecked(at index: Int, checked: Bool, linesCount: Int? = nil) {
        let count = linesCount ?? ingredientLines.count
        var parts = ingredientCheckmarks.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        while parts.count < count { parts.append("0") }
        guard index >= 0, index < parts.count else { return }
        parts[index] = checked ? "1" : "0"
        ingredientCheckmarks = parts.joined(separator: ",")
    }

    func toggleIngredientCheck(at index: Int, linesCount: Int? = nil) {
        setIngredientChecked(at: index, checked: !ingredientChecked(at: index), linesCount: linesCount)
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

    /// One-time: existing recipes before `estimatedServings` default to 1 serving.
    @MainActor
    static func migrateEstimatedServingsOnce(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: servingsMigrationDefaultsKey) else { return }
        let desc = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.estimatedServings <= 0 })
        if let rows = try? modelContext.fetch(desc) {
            for row in rows { row.estimatedServings = 1 }
            try? modelContext.save()
        }
        UserDefaults.standard.set(true, forKey: servingsMigrationDefaultsKey)
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

// MARK: - Ingredient line parsing & serving scale

enum IngredientLine {
    private static let storageSeparator = "\t"

    static func join(name: String, amount: String) -> String {
        let item = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let qty = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty else { return qty }
        guard !qty.isEmpty else { return item }
        return "\(item)\(storageSeparator)\(qty)"
    }

    static func parse(_ line: String) -> (name: String, amount: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }
        if let tab = trimmed.firstIndex(of: "\t") {
            let name = String(trimmed[..<tab]).trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = String(trimmed[trimmed.index(after: tab)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (name, amount)
        }
        if let range = trimmed.range(of: " - ") {
            let name = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (name, amount)
        }
        return (trimmed, "")
    }
}

enum IngredientAmountScaler {
    private static let skipPhrases = [
        "as needed", "to taste", "optional", "pinch", "dash", "handful", "some", "a few",
    ]

    static func scaledAmount(_ amount: String, factor: Double) -> String {
        guard factor.isFinite, abs(factor - 1.0) > 0.001 else { return amount }
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return amount }
        let lower = trimmed.lowercased()
        if skipPhrases.contains(where: { lower.contains($0) }) { return amount }

        guard let match = leadingQuantity(in: trimmed) else { return amount }
        let scaled = match.value * factor
        guard scaled > 0 else { return amount }
        let formatted = formatQuantity(scaled)
        let suffix = trimmed[match.suffixStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? formatted : "\(formatted) \(suffix)"
    }

    private struct QuantityMatch {
        let value: Double
        let suffixStart: String.Index
    }

    private static func leadingQuantity(in text: String) -> QuantityMatch? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Mixed number: "1 1/2 tbsp"
        if let mixed = trimmed.range(of: #"^(\d+)\s+(\d+)/(\d+)"#, options: .regularExpression) {
            let token = String(trimmed[mixed])
            let parts = token.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2, let whole = Double(parts[0]) {
                let fracParts = parts[1].split(separator: "/")
                if fracParts.count == 2,
                   let num = Double(fracParts[0]),
                   let den = Double(fracParts[1]), den != 0 {
                    return QuantityMatch(value: whole + num / den, suffixStart: mixed.upperBound)
                }
            }
        }

        // Simple fraction: "1/2 cup"
        if let frac = trimmed.range(of: #"^(\d+)/(\d+)"#, options: .regularExpression) {
            let token = String(trimmed[frac])
            let fracParts = token.split(separator: "/")
            if fracParts.count == 2,
               let num = Double(fracParts[0]),
               let den = Double(fracParts[1]), den != 0 {
                return QuantityMatch(value: num / den, suffixStart: frac.upperBound)
            }
        }

        // Decimal / whole: "2.5 tbsp", "2 tbsp"
        if let decimal = trimmed.range(of: #"^(\d+(?:[.,]\d+)?)"#, options: .regularExpression) {
            let token = String(trimmed[decimal]).replacingOccurrences(of: ",", with: ".")
            if let value = Double(token) {
                return QuantityMatch(value: value, suffixStart: decimal.upperBound)
            }
        }

        return nil
    }

    private static func formatQuantity(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if abs(rounded - rounded.rounded()) < 0.06 {
            return String(Int(rounded.rounded()))
        }
        let commonFractions: [(Double, String)] = [
            (0.25, "1/4"), (0.33, "1/3"), (0.5, "1/2"), (0.67, "2/3"), (0.75, "3/4"),
        ]
        let whole = floor(rounded)
        let frac = rounded - whole
        if let match = commonFractions.min(by: { abs($0.0 - frac) < abs($1.0 - frac) }), abs(match.0 - frac) < 0.08 {
            if whole >= 1 { return "\(Int(whole)) \(match.1)" }
            return match.1
        }
        var text = String(format: "%.1f", rounded)
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text
    }
}
