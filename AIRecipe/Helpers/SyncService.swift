import Foundation
import SwiftData
import Supabase

// MARK: - DTOs

/// JSON payload stored in `synced_recipes.data` (round-trips all `Recipe` fields except sync columns).
struct RecipeSyncPayload: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var source: String
    var sourceURL: String
    var creator: String
    var timestamp: String
    var ingredients: String
    var estimatedServings: Int?
    var estimatedCookingMinutes: Int
    var prepMinutes: Int
    var totalSteps: Int
    var triedBefore: Bool
    var notes: String
    var createdAt: Date
    var rating: Int
    var downloadedVideoURL: String
    var videoPlaybackURL: String?
    var stepTimestampsContent: String?
    var dishHeroTimestampSeconds: Double
    var stepsContent: String
    var ingredientCheckmarks: String
    /// Present for new clients; older `data` JSON may omit this key.
    var ownerUserId: String?
    var isBookmarked: Bool?
    var nutritionCalories: Int?
    var nutritionProteinGrams: Int?
    var nutritionCarbsGrams: Int?
    var nutritionFatGrams: Int?
}

private struct RecipeCloudRowUpsert: Encodable, Sendable {
    let id: String
    let updated_at: Date
    let deleted_at: Date?
    let user_id: UUID
    let data: RecipeSyncPayload
}

private struct RecipeCloudRow: Decodable, Sendable {
    let id: String
    let updated_at: Date
    let deleted_at: Date?
    let user_id: UUID
    let data: RecipeSyncPayload
}

// MARK: - Errors

enum RecipeSyncError: Error, LocalizedError {
    case notPro
    case notAuthenticated
    case modelSaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notPro: return "Cloud sync is available on Pro."
        case .notAuthenticated: return "Sign in to sync recipes."
        case .modelSaveFailed(let message): return message
        }
    }
}

// MARK: - Service

/// Pro-only bidirectional sync between SwiftData and Supabase `synced_recipes`.
final class SyncService: @unchecked Sendable {
    static let shared = SyncService()

    static let tableName = "synced_recipes"

    private static let lastSyncKeyPrefix = "recipeSync.lastSync."
    private static let pushChunkSize = 40

    private let modelIsolation = DispatchQueue(label: "com.airecipe.recipeSyncModel", qos: .utility)

    private init() {}

    private static func lastSyncStorageKey(userId: UUID) -> String {
        lastSyncKeyPrefix + userId.uuidString.lowercased()
    }

    private func readLastSync(for userId: UUID) -> Date? {
        UserDefaults.standard.object(forKey: Self.lastSyncStorageKey(userId: userId)) as? Date
    }

    private func writeLastSync(_ date: Date, for userId: UUID) {
        UserDefaults.standard.set(date, forKey: Self.lastSyncStorageKey(userId: userId))
    }

    @MainActor
    private func requirePro() throws {
        guard SubscriptionManager.shared.isPremium else { throw RecipeSyncError.notPro }
    }

    private func requireUserId() async throws -> UUID {
        do {
            let session = try await SupabaseService.shared.client.auth.session
            return session.user.id
        } catch {
            throw RecipeSyncError.notAuthenticated
        }
    }

    /// Push local changes, then pull remote changes. Call only after `requirePro` / auth checks if needed.
    func sync(modelContainer: ModelContainer) async throws {
        try await requirePro()
        let userId = try await requireUserId()
        let since = readLastSync(for: userId) ?? .distantPast

        let rowsToPush = try await fetchLocalsToPush(modelContainer: modelContainer, since: since, userId: userId)
        if !rowsToPush.isEmpty {
            for chunk in Self.chunked(rowsToPush, size: Self.pushChunkSize) {
                try await SupabaseService.shared.client
                    .from(Self.tableName)
                    .upsert(chunk, onConflict: "id")
                    .execute()
            }
        }

        let remoteRows: [RecipeCloudRow] = try await SupabaseService.shared.client
            .from(Self.tableName)
            .select()
            .eq("user_id", value: userId)
            .gt("updated_at", value: since)
            .execute()
            .value

        if !remoteRows.isEmpty {
            try await applyRemoteRows(remoteRows, modelContainer: modelContainer)
            await MainActor.run {
                let context = ModelContext(modelContainer)
                _ = CookbookService.ensureLibrary(for: userId.uuidString, modelContext: context)
            }
        }

        writeLastSync(Date(), for: userId)
    }

    /// Push only (e.g. after save). No-op if not Pro or not signed in.
    func push(modelContainer: ModelContainer) async {
        do {
            try await requirePro()
            let userId = try await requireUserId()
            let since = readLastSync(for: userId) ?? .distantPast
            let rowsToPush = try await fetchLocalsToPush(modelContainer: modelContainer, since: since, userId: userId)
            guard !rowsToPush.isEmpty else { return }
            for chunk in Self.chunked(rowsToPush, size: Self.pushChunkSize) {
                try await SupabaseService.shared.client
                    .from(Self.tableName)
                    .upsert(chunk, onConflict: "id")
                    .execute()
            }
        } catch RecipeSyncError.notPro, RecipeSyncError.notAuthenticated {
            return
        } catch {
            #if DEBUG
            print("SyncService.push failed: \(error)")
            #endif
        }
    }

    /// Full sync for Home `onAppear`; errors are swallowed.
    func silentSync(modelContainer: ModelContainer) async {
        do {
            try await sync(modelContainer: modelContainer)
        } catch RecipeSyncError.notPro, RecipeSyncError.notAuthenticated {
            return
        } catch {
            #if DEBUG
            print("SyncService.silentSync failed: \(error)")
            #endif
        }
    }

    // MARK: - Model helpers

    private func fetchLocalsToPush(
        modelContainer: ModelContainer,
        since: Date,
        userId: UUID
    ) async throws -> [RecipeCloudRowUpsert] {
        try await withCheckedThrowingContinuation { continuation in
            modelIsolation.async {
                do {
                    let context = ModelContext(modelContainer)
                    let descriptor = FetchDescriptor<Recipe>()
                    let all = try context.fetch(descriptor)
                    let uidString = userId.uuidString
                    let dirty = all.filter {
                        $0.updatedAt > since && $0.ownerUserId == uidString
                    }
                    let rows = dirty.map { Self.makeUpsertRow(recipe: $0, userId: userId) }
                    continuation.resume(returning: rows)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func applyRemoteRows(_ rows: [RecipeCloudRow], modelContainer: ModelContainer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            modelIsolation.async {
                do {
                    let context = ModelContext(modelContainer)
                    for row in rows {
                        try Self.reconcile(row: row, in: context)
                    }
                    try context.save()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: RecipeSyncError.modelSaveFailed(error.localizedDescription))
                }
            }
        }
    }

    private static func makeUpsertRow(recipe: Recipe, userId: UUID) -> RecipeCloudRowUpsert {
        RecipeCloudRowUpsert(
            id: recipe.id,
            updated_at: recipe.updatedAt,
            deleted_at: recipe.deletedAt,
            user_id: userId,
            data: RecipeSyncPayload(from: recipe)
        )
    }

    private static func reconcile(row: RecipeCloudRow, in context: ModelContext) throws {
        let remoteId = row.id
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == remoteId })
        let existing = try context.fetch(descriptor).first

        if row.deleted_at != nil {
            if let existing {
                context.delete(existing)
            }
            return
        }

        if let local = existing {
            guard row.updated_at > local.updatedAt else { return }
            local.applySyncPayload(row.data)
            local.ownerUserId = row.user_id.uuidString
            local.updatedAt = row.updated_at
            local.deletedAt = row.deleted_at
            return
        }

        let inserted = Recipe(
            id: row.id,
            ownerUserId: row.user_id.uuidString,
            title: row.data.title,
            source: RecipeSource(rawValue: row.data.source) ?? .youtube,
            sourceURL: row.data.sourceURL,
            creator: row.data.creator,
            timestamp: row.data.timestamp,
            ingredients: row.data.ingredients,
            estimatedServings: max(1, row.data.estimatedServings ?? 1),
            estimatedCookingMinutes: row.data.estimatedCookingMinutes,
            prepMinutes: row.data.prepMinutes,
            totalSteps: row.data.totalSteps,
            triedBefore: row.data.triedBefore,
            notes: row.data.notes,
            stepsContent: row.data.stepsContent,
            ingredientCheckmarks: row.data.ingredientCheckmarks,
            downloadedVideoURL: row.data.downloadedVideoURL,
            videoPlaybackURL: row.data.videoPlaybackURL ?? "",
            stepTimestampsContent: row.data.stepTimestampsContent ?? "",
            dishHeroTimestampSeconds: row.data.dishHeroTimestampSeconds,
            rating: row.data.rating,
            isBookmarked: row.data.isBookmarked ?? false,
            nutritionCalories: max(0, row.data.nutritionCalories ?? 0),
            nutritionProteinGrams: max(0, row.data.nutritionProteinGrams ?? 0),
            nutritionCarbsGrams: max(0, row.data.nutritionCarbsGrams ?? 0),
            nutritionFatGrams: max(0, row.data.nutritionFatGrams ?? 0),
            createdAt: row.data.createdAt,
            updatedAt: row.updated_at,
            deletedAt: row.deleted_at
        )
        context.insert(inserted)
    }

    private static func chunked<T>(_ array: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [array] }
        return stride(from: 0, to: array.count, by: size).map {
            Array(array[$0..<min($0 + size, array.count)])
        }
    }
}

// MARK: - Recipe ↔ payload

extension RecipeSyncPayload {
    init(from recipe: Recipe) {
        self.init(
            id: recipe.id,
            title: recipe.title,
            source: recipe.source,
            sourceURL: recipe.sourceURL,
            creator: recipe.creator,
            timestamp: recipe.timestamp,
            ingredients: recipe.ingredients,
            estimatedServings: recipe.estimatedServings,
            estimatedCookingMinutes: recipe.estimatedCookingMinutes,
            prepMinutes: recipe.prepMinutes,
            totalSteps: recipe.totalSteps,
            triedBefore: recipe.triedBefore,
            notes: recipe.notes,
            createdAt: recipe.createdAt,
            rating: recipe.rating,
            downloadedVideoURL: recipe.downloadedVideoURL,
            videoPlaybackURL: recipe.videoPlaybackURL,
            stepTimestampsContent: recipe.stepTimestampsContent,
            dishHeroTimestampSeconds: recipe.dishHeroTimestampSeconds,
            stepsContent: recipe.stepsContent,
            ingredientCheckmarks: recipe.ingredientCheckmarks,
            ownerUserId: recipe.ownerUserId,
            isBookmarked: recipe.isBookmarked,
            nutritionCalories: recipe.nutritionCalories > 0 ? recipe.nutritionCalories : nil,
            nutritionProteinGrams: recipe.nutritionProteinGrams > 0 ? recipe.nutritionProteinGrams : nil,
            nutritionCarbsGrams: recipe.nutritionCarbsGrams > 0 ? recipe.nutritionCarbsGrams : nil,
            nutritionFatGrams: recipe.nutritionFatGrams > 0 ? recipe.nutritionFatGrams : nil
        )
    }
}

extension Recipe {
    fileprivate func applySyncPayload(_ payload: RecipeSyncPayload) {
        title = payload.title
        source = payload.source
        sourceURL = payload.sourceURL
        creator = payload.creator
        timestamp = payload.timestamp
        ingredients = payload.ingredients
        estimatedServings = max(1, payload.estimatedServings ?? 1)
        estimatedCookingMinutes = payload.estimatedCookingMinutes
        prepMinutes = payload.prepMinutes
        totalSteps = payload.totalSteps
        triedBefore = payload.triedBefore
        notes = payload.notes
        createdAt = payload.createdAt
        rating = payload.rating
        downloadedVideoURL = payload.downloadedVideoURL
        videoPlaybackURL = payload.videoPlaybackURL ?? ""
        stepTimestampsContent = payload.stepTimestampsContent ?? ""
        dishHeroTimestampSeconds = payload.dishHeroTimestampSeconds
        stepsContent = payload.stepsContent
        ingredientCheckmarks = payload.ingredientCheckmarks
        isBookmarked = payload.isBookmarked ?? false
        if let calories = payload.nutritionCalories { nutritionCalories = max(0, calories) }
        if let protein = payload.nutritionProteinGrams { nutritionProteinGrams = max(0, protein) }
        if let carbs = payload.nutritionCarbsGrams { nutritionCarbsGrams = max(0, carbs) }
        if let fat = payload.nutritionFatGrams { nutritionFatGrams = max(0, fat) }
        if let o = payload.ownerUserId, !o.isEmpty {
            ownerUserId = o
        }
    }
}
