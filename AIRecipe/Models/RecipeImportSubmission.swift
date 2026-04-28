import Foundation
import SwiftData

/// Status for a row on the Imports tab (link or Photos video submitted for analysis).
enum RecipeImportStatus: String, Codable, CaseIterable {
    case processing
    case ready
    case failed
}

@Model
final class RecipeImportSubmission {
    var id: UUID
    /// `"link"` or `"photo"`.
    var importKind: String
    /// Original share URL, or a display tag while processing a photo import.
    var sourceURL: String
    /// Relative path under Application Support for a copied video (photo imports only).
    var pendingVideoRelPath: String?
    var languageCode: String
    /// Backend queue id in `import_jobs` (empty until enqueue succeeds).
    var backendJobId: String
    var statusRaw: String
    var errorMessage: String
    var createdAt: Date

    // Filled when analysis succeeds (`ready` → user can add to Home or delete).
    var readyTitle: String
    var readyCreator: String
    var readyNotes: String
    var readyIngredients: String
    var readySteps: String
    var readyPrepMinutes: Int
    var readyCookMinutes: Int
    var readyTotalSteps: Int
    var readySource: String
    var readySourceURL: String
    var readyDownloadedVideoURL: String
    var readyDishHeroSeconds: Double

    var status: RecipeImportStatus {
        get { RecipeImportStatus(rawValue: statusRaw) ?? .processing }
        set { statusRaw = newValue.rawValue }
    }

    init(importKind: String, sourceURL: String, languageCode: String, pendingVideoRelPath: String? = nil) {
        self.id = UUID()
        self.importKind = importKind
        self.sourceURL = sourceURL
        self.pendingVideoRelPath = pendingVideoRelPath
        self.languageCode = languageCode
        self.backendJobId = ""
        self.statusRaw = RecipeImportStatus.processing.rawValue
        self.errorMessage = ""
        self.createdAt = Date()
        self.readyTitle = ""
        self.readyCreator = ""
        self.readyNotes = ""
        self.readyIngredients = ""
        self.readySteps = ""
        self.readyPrepMinutes = 0
        self.readyCookMinutes = 0
        self.readyTotalSteps = 0
        self.readySource = RecipeSource.youtube.rawValue
        self.readySourceURL = ""
        self.readyDownloadedVideoURL = ""
        self.readyDishHeroSeconds = 0
    }
}
