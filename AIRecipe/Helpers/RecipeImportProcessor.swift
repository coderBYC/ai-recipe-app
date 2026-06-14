import Foundation
import SwiftData

enum RecipeImportProcessor {
    private static let importsDirName = "PendingImportVideos"

    private static func languageCodeFromSettings() -> String {
        let languageSetting = UserDefaults.standard.string(forKey: "settings.language") ?? "System"
        switch languageSetting {
        case "Mandarin": return "zh"
        case "Spanish": return "es"
        case "Hindi": return "hi"
        case "Korean": return "ko"
        case "System": return "en"
        default: return "en"
        }
    }

    /// Share extension **Close**: create an Imports row and start the backend job without presenting `PasteLinkView`.
    /// - Returns: `true` if a new import job was enqueued.
    @MainActor
    static func enqueueSharedLinkImportSilently(
        url: String,
        container: ModelContainer,
        knownImportsUsedToday: Int? = nil,
        presentPaywallOnLimit: Bool = true
    ) async -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return false }

        let ctx = ModelContext(container)

        func insertFailed(_ message: String) {
            let sub = RecipeImportSubmission(
                importKind: "link",
                sourceURL: trimmed,
                languageCode: languageCodeFromSettings()
            )
            sub.status = .failed
            sub.errorMessage = message
            ctx.insert(sub)
            try? ctx.save()
        }

        guard await SupabaseService.shared.currentUserIdString() != nil else {
            insertFailed("Sign in to import shared links.")
            return false
        }

        await SubscriptionManager.shared.checkStatus()
        if !SubscriptionManager.shared.isPremium {
            do {
                let used: Int
                if let knownImportsUsedToday {
                    used = knownImportsUsedToday
                } else {
                    used = try await SupabaseService.shared.fetchAIUsageCount()
                }
                if FreeTierLimits.isImportLimitReached(usedCount: used) {
                    if presentPaywallOnLimit {
                        insertFailed("You’ve reached the free import limit. Subscribe to continue.")
                        NotificationCenter.default.post(name: .presentRevenueCatPaywall, object: nil)
                    }
                    return false
                }
            } catch {
                // If usage can’t be read, allow import (same tolerance as PasteLinkView).
            }
        }

        let submission = RecipeImportSubmission(
            importKind: "link",
            sourceURL: trimmed,
            languageCode: languageCodeFromSettings()
        )
        ctx.insert(submission)
        try? ctx.save()
        ctx.processPendingChanges()
        let sid = submission.id
        await startLinkJob(submissionId: sid, container: container)
        return true
    }

    private static func urlNeedsDownloadedVideo(_ raw: String) -> Bool {
        let u = raw.lowercased()
        if u.contains("tiktok.com") || u.contains("vt.tiktok.com") { return true }
        if u.contains("instagram.com") || u.contains("instagr.am") { return true }
        return false
    }

    static func importsDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let dir = base.appending(path: importsDirName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies a temp photo-picker file into Application Support; returns path relative to Application Support.
    static func copyVideoForPendingJob(from tempURL: URL) throws -> String {
        let dir = try importsDirectory()
        let name = "\(UUID().uuidString).mp4"
        let dest = dir.appending(path: name)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: tempURL, to: dest)
        return "\(importsDirName)/\(name)"
    }

    static func resolvedVideoURL(relPath: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = base.appending(path: relPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func removePendingVideoIfAny(relPath: String?) {
        guard let relPath, !relPath.isEmpty, let url = resolvedVideoURL(relPath: relPath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    static func markSubmissionFailed(submissionId: UUID, container: ModelContainer, message: String) {
        let ctx = ModelContext(container)
        let sid = submissionId
        let desc = FetchDescriptor<RecipeImportSubmission>(predicate: #Predicate { $0.id == sid })
        guard let sub = try? ctx.fetch(desc).first else { return }
        sub.status = .failed
        sub.errorMessage = message
        try? ctx.save()
    }

    @MainActor
    static func startLinkJob(submissionId: UUID, container: ModelContainer) async {
        let ctx = ModelContext(container)
        let sid = submissionId
        let desc = FetchDescriptor<RecipeImportSubmission>(predicate: #Predicate { $0.id == sid })
        guard let sub = try? ctx.fetch(desc).first else { return }
        guard sub.importKind == "link" else { return }
        do {
            guard let userId = await SupabaseService.shared.currentUserIdString() else {
                sub.status = .failed
                sub.errorMessage = "Not signed in."
                try? ctx.save()
                return
            }
            let isPremium = await MainActor.run { SubscriptionManager.shared.isPremium }
            let queued = try await RecipeBackendService.shared.enqueueImport(
                url: sub.sourceURL,
                language: sub.languageCode,
                userId: userId,
                isPro: isPremium
            )
            sub.backendJobId = queued.job_id
            sub.status = .processing
            sub.errorMessage = ""
            try? ctx.save()
        } catch {
            sub.status = .failed
            sub.errorMessage = error.localizedDescription
            try? ctx.save()
        }
    }

    @MainActor
    static func syncRemoteLinkJobs(container: ModelContainer) async {
        guard let userId = await SupabaseService.shared.currentUserIdString() else { return }
        let ctx = ModelContext(container)
        let desc = FetchDescriptor<RecipeImportSubmission>(
            predicate: #Predicate<RecipeImportSubmission> { $0.importKind == "link" }
        )
        guard let locals = try? ctx.fetch(desc), !locals.isEmpty else { return }
        let byJobId = Dictionary(uniqueKeysWithValues: locals.compactMap { sub in
            let id = sub.backendJobId.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : (id, sub)
        })
        if byJobId.isEmpty { return }
        do {
            let remoteJobs = try await RecipeBackendService.shared.fetchImportJobs(userId: userId, limit: 200)
            var changed = false
            for job in remoteJobs {
                guard let local = byJobId[job.id] else { continue }
                switch job.status.lowercased() {
                case "ready":
                    if let response = job.parsedAnalyzeResponse {
                        response.applyToPendingImport(local, finalSourceURL: local.sourceURL)
                        if local.readyStepTimestamps.isEmpty, let raw = job.stepTimestampsFromRawJSON {
                            local.readyStepTimestamps = raw
                        }
                        if local.readyVideoPlaybackURL.isEmpty, let video = job.videoURLFromRawJSON {
                            local.readyVideoPlaybackURL = RecipeAnalyzeResponse.storedVideoPlaybackURLString(video_url: video)
                        }
                        local.status = .ready
                        local.errorMessage = ""
                        changed = true
                    }
                case "failed":
                    local.status = .failed
                    local.errorMessage = job.error_log ?? "Import failed."
                    changed = true
                case "processing", "pending":
                    if local.status != .processing {
                        local.status = .processing
                        changed = true
                    }
                default:
                    break
                }
            }
            if changed { try? ctx.save() }
        } catch {
            // keep silent; caller can poll again
        }
    }

    @MainActor
    static func startPhotoJob(submissionId: UUID, container: ModelContainer) async {
        let ctx = ModelContext(container)
        let sid = submissionId
        let desc = FetchDescriptor<RecipeImportSubmission>(predicate: #Predicate { $0.id == sid })
        guard let sub = try? ctx.fetch(desc).first else { return }
        guard sub.importKind == "photo" else { return }
        guard let rel = sub.pendingVideoRelPath, let fileURL = resolvedVideoURL(relPath: rel) else {
            sub.status = .failed
            sub.errorMessage = "Video file missing."
            try? ctx.save()
            return
        }
        let lang = sub.languageCode
        do {
            guard let userId = await SupabaseService.shared.currentUserIdString() else {
                sub.status = .failed
                sub.errorMessage = "Not signed in."
                try? ctx.save()
                return
            }
            await SubscriptionManager.shared.checkStatus()
            let isPremium = SubscriptionManager.shared.isPremium
            let response = try await RecipeBackendService.shared.analyzeUploadedVideo(
                fileURL: fileURL,
                language: lang,
                userId: userId,
                isPro: isPremium
            )
            let finalSource = "photos://import/\(UUID().uuidString)"
            response.applyToPendingImport(sub, finalSourceURL: finalSource)
            sub.status = .ready
            removePendingVideoIfAny(relPath: sub.pendingVideoRelPath)
            sub.pendingVideoRelPath = nil
            try? ctx.save()
        } catch {
            sub.status = .failed
            sub.errorMessage = error.localizedDescription
            try? ctx.save()
        }
    }

    /// Builds a `Recipe` from a finished import (not inserted). Used for list preview and for `finalizeImport`.
    static func makeRecipe(from sub: RecipeImportSubmission, ownerUserId: String = Recipe.localOnboardingOwnerPlaceholder) -> Recipe {
        let source = RecipeSource(rawValue: sub.readySource) ?? .youtube
        return Recipe(
            id: sub.id.uuidString,
            ownerUserId: ownerUserId,
            title: sub.readyTitle.isEmpty ? "Imported recipe" : sub.readyTitle,
            source: source,
            sourceURL: sub.readySourceURL,
            creator: sub.readyCreator,
            timestamp: "",
            ingredients: sub.readyIngredients,
            estimatedServings: max(1, sub.readyEstimatedServings),
            estimatedCookingMinutes: sub.readyCookMinutes,
            prepMinutes: sub.readyPrepMinutes,
            totalSteps: sub.readyTotalSteps,
            triedBefore: false,
            notes: sub.readyNotes,
            stepsContent: sub.readySteps,
            downloadedVideoURL: sub.readyDownloadedVideoURL,
            videoPlaybackURL: sub.readyVideoPlaybackURL,
            stepTimestampsContent: sub.readyStepTimestamps,
            dishHeroTimestampSeconds: sub.readyDishHeroSeconds,
            rating: 0,
            nutritionCalories: sub.readyNutritionCalories,
            nutritionProteinGrams: sub.readyNutritionProteinGrams,
            nutritionCarbsGrams: sub.readyNutritionCarbsGrams,
            nutritionFatGrams: sub.readyNutritionFatGrams
        )
    }

    /// Inserts the recipe into Home, removes the submission, returns the persisted recipe.
    @discardableResult
    @MainActor
    static func approveSubmission(
        _ sub: RecipeImportSubmission,
        modelContext: ModelContext,
        cookbookId: String? = nil
    ) -> Recipe {
        let owner = SupabaseService.shared.client.auth.currentSession?.user.id.uuidString ?? Recipe.localOnboardingOwnerPlaceholder
        let recipe = makeRecipe(from: sub, ownerUserId: owner)
        let chosenCookbookId = cookbookId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !chosenCookbookId.isEmpty {
            recipe.cookbookId = chosenCookbookId
            CookbookService.setActiveCookbookId(chosenCookbookId, ownerUserId: owner)
        } else {
            recipe.cookbookId = CookbookService.cookbookIdForNewRecipe(ownerUserId: owner, modelContext: modelContext)
        }
        recipe.updatedAt = Date()
        modelContext.insert(recipe)
        removePendingVideoIfAny(relPath: sub.pendingVideoRelPath)
        modelContext.delete(sub)
        try? modelContext.save()
        Task { await SyncService.shared.push(modelContainer: modelContext.container) }
        return recipe
    }
}
