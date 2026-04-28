import Foundation
import SwiftData

enum RecipeImportProcessor {
    private static let importsDirName = "PendingImportVideos"

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
            let queued = try await RecipeBackendService.shared.enqueueImport(
                url: sub.sourceURL,
                language: sub.languageCode,
                userId: userId
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
    static func makeRecipe(from sub: RecipeImportSubmission) -> Recipe {
        let source = RecipeSource(rawValue: sub.readySource) ?? .youtube
        return Recipe(
            title: sub.readyTitle.isEmpty ? "Imported recipe" : sub.readyTitle,
            source: source,
            sourceURL: sub.readySourceURL,
            creator: sub.readyCreator,
            timestamp: "",
            ingredients: sub.readyIngredients,
            estimatedCookingMinutes: sub.readyCookMinutes,
            prepMinutes: sub.readyPrepMinutes,
            totalSteps: sub.readyTotalSteps,
            triedBefore: false,
            notes: sub.readyNotes,
            stepsContent: sub.readySteps,
            downloadedVideoURL: sub.readyDownloadedVideoURL,
            dishHeroTimestampSeconds: sub.readyDishHeroSeconds,
            rating: 0
        )
    }

    /// Inserts the recipe into Home, removes the submission, returns the persisted recipe.
    @discardableResult
    @MainActor
    static func approveSubmission(_ sub: RecipeImportSubmission, modelContext: ModelContext) -> Recipe {
        let recipe = makeRecipe(from: sub)
        modelContext.insert(recipe)
        removePendingVideoIfAny(relPath: sub.pendingVideoRelPath)
        modelContext.delete(sub)
        try? modelContext.save()
        return recipe
    }
}
