import SwiftUI
import SwiftData
import Supabase
import RevenueCat
import UserNotifications
import PostHog
import GoogleSignIn
import GoogleSignInSwift

extension Notification.Name {
    /// After enqueueing a link/photo import, switch tab bar to Imports.
    static let switchToImportsTab = Notification.Name("switchToImportsTab")
    static let importSharedRecipeLink = Notification.Name("importSharedRecipeLink")
    /// Posted after `PendingAppDeepLink.store` when handling `airecipe://settings|terms|privacy`.
    static let openAppDeepLink = Notification.Name("openAppDeepLink")
    /// User tapped the “Wanna Build Recipe?” nudge or deep link `airecipe://photo-recipe`.
    static let openPhotoRecipeImport = Notification.Name("openPhotoRecipeImport")
    /// Notifications denied: show an in-app banner instead of a system notification.
    static let savedVideoRecipeSuggestion = Notification.Name("savedVideoRecipeSuggestion")
    /// Present `RevenueCatUI.PaywallView` from the root tab UI (e.g. share import hit free tier).
    static let presentRevenueCatPaywall = Notification.Name("presentRevenueCatPaywall")
    /// Dismiss recipe detail and open Bookmarks sheet on Home.
    static let openBookmarksSheet = Notification.Name("openBookmarksSheet")
}

/// Deep links: `airecipe://settings`, `airecipe://terms`, `airecipe://privacy` (RevenueCat paywall buttons, Safari tests).
enum PendingAppDeepLink {
    static let userDefaultsKey = "pendingAppDeepLinkRoute"
    static let settings = "settings"
    static let terms = "terms"
    static let privacy = "privacy"

    static func store(_ route: String) {
        UserDefaults.standard.set(route, forKey: userDefaultsKey)
    }

    /// Returns and clears the pending route, if any.
    static func consume() -> String? {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// Share Extension stores the URL in the App Group before opening `airecipe://import` (short URL).
enum PendingRecipeImport {
    static let appGroupSuiteName = "group.com.airecipe.app"
    static let userDefaultsKey = "pendingSharedRecipeURL"
    /// `"silent"` = queue import without sheet (user closed share extension). `"sheet"` = show `PasteLinkView` auto-process.
    static let presentationModeKey = "pendingSharedRecipePresentationMode"
    /// URLs the user queued from the share extension (close / dismiss); drained when the main app runs while signed in.
    static let silentImportQueueKey = "silentSharedImportURLQueue"

    private static var groupDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupSuiteName)
    }

    private static func mergeUniqueURLQueues(_ existing: [String], _ incoming: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in existing + incoming {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t).inserted else { continue }
            out.append(t)
        }
        return out
    }

    private static func appendToStandardSilentQueue(_ url: String) {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var q = (UserDefaults.standard.array(forKey: silentImportQueueKey) as? [String]) ?? []
        guard !q.contains(t) else { return }
        q.append(t)
        UserDefaults.standard.set(q, forKey: silentImportQueueKey)
    }

    /// Merges App Group → standard: silent URL queue + optional single-URL handoff for `airecipe://import`.
    static func migratePendingFromAppGroupToStandardIfNeeded() {
        if let groupQ = groupDefaults?.array(forKey: silentImportQueueKey) as? [String], !groupQ.isEmpty {
            let stdQ = (UserDefaults.standard.array(forKey: silentImportQueueKey) as? [String]) ?? []
            UserDefaults.standard.set(mergeUniqueURLQueues(stdQ, groupQ), forKey: silentImportQueueKey)
            groupDefaults?.removeObject(forKey: silentImportQueueKey)
        }

        guard let raw = groupDefaults?.string(forKey: userDefaultsKey),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = UserDefaults.standard.string(forKey: userDefaultsKey),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendToStandardSilentQueue(trimmed)
            groupDefaults?.removeObject(forKey: userDefaultsKey)
            groupDefaults?.removeObject(forKey: presentationModeKey)
            return
        }

        UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
        let rawMode = groupDefaults?.string(forKey: presentationModeKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let mode = rawMode == "silent" ? "silent" : "sheet"
        UserDefaults.standard.set(mode, forKey: presentationModeKey)
        groupDefaults?.removeObject(forKey: userDefaultsKey)
        groupDefaults?.removeObject(forKey: presentationModeKey)
    }

    /// Reads URL + presentation from the App Group and removes them (used when handling `airecipe://import`).
    static func takeImportHandoffFromAppGroupConsuming() -> (url: String, presentation: String)? {
        guard let raw = groupDefaults?.string(forKey: userDefaultsKey) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            groupDefaults?.removeObject(forKey: userDefaultsKey)
            groupDefaults?.removeObject(forKey: presentationModeKey)
            return nil
        }
        let rawMode = groupDefaults?.string(forKey: presentationModeKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let mode = rawMode == "silent" ? "silent" : "sheet"
        groupDefaults?.removeObject(forKey: userDefaultsKey)
        groupDefaults?.removeObject(forKey: presentationModeKey)
        return (trimmed, mode)
    }

    static func clearAppGroupPending() {
        groupDefaults?.removeObject(forKey: userDefaultsKey)
        groupDefaults?.removeObject(forKey: presentationModeKey)
    }
}

@main
struct AIRecipeApp: App {
    /// Retain delegate for `Purchases.shared` (SDK holds weak reference).
    private static let revenueCatDelegate = RevenueCatPurchasesDelegate()
   
    init() {
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        _ = PostHogConfig(
                    apiKey: "phc_oJMeDDAjsLWkGbBqJ2R5LRYd6whaSHRvR32ADynEQefS",
                    host: "https://us.posthog.com")
        let rcKey = AppSecrets.revenueCatPublicKey
        guard !rcKey.isEmpty else {
            fatalError(AppSecrets.configurationHint)
        }
        Purchases.configure(withAPIKey: rcKey)
        Purchases.shared.delegate = Self.revenueCatDelegate
        UNUserNotificationCenter.current().delegate = RecipeNotificationCenterDelegate.shared
        PhotoLibraryRecipeNotifier.shared.registerCategories()
        GoogleSignInService.configure()
    }
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            Cookbook.self,
            PlannedMeal.self,
            RecipeImportSubmission.self,
            FridgeItem.self,
        ])
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("SwiftData: could not resolve application support directory.")
        }
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let primaryURL = appSupport.appending(path: "default.store")
        let recoveryURL = appSupport.appending(path: "default.recovery.store")

        func relatedStoreFileURLs(for storeURL: URL) -> [URL] {
            let base = storeURL.path
            return [
                storeURL,
                URL(fileURLWithPath: base + "-shm"),
                URL(fileURLWithPath: base + "-wal"),
            ]
        }

        func openContainer(at url: URL) throws -> ModelContainer {
            let config = ModelConfiguration(schema: schema, url: url)
            return try ModelContainer(for: schema, configurations: [config])
        }

        func preserveStoreCopy(at storeURL: URL, backupPrefix: String) {
            let fm = FileManager.default
            let stamp = Int(Date().timeIntervalSince1970)
            for src in relatedStoreFileURLs(for: storeURL) where fm.fileExists(atPath: src.path) {
                let backupURL = appSupport.appending(
                    path: "\(backupPrefix)-\(stamp)-\(src.lastPathComponent)",
                    directoryHint: .notDirectory
                )
                try? fm.copyItem(at: src, to: backupURL)
                #if DEBUG
                print("SwiftData: preserved store at \(backupURL.path)")
                #endif
            }
        }

        /// Moves aside an incompatible store so a fresh file can be created at the same path.
        func archiveStoreFiles(at storeURL: URL, archivePrefix: String) {
            let fm = FileManager.default
            let stamp = Int(Date().timeIntervalSince1970)
            for src in relatedStoreFileURLs(for: storeURL) where fm.fileExists(atPath: src.path) {
                let archivedURL = appSupport.appending(
                    path: "\(archivePrefix)-\(stamp)-\(src.lastPathComponent)",
                    directoryHint: .notDirectory
                )
                try? fm.moveItem(at: src, to: archivedURL)
                #if DEBUG
                print("SwiftData: archived store at \(archivedURL.path)")
                #endif
            }
        }

        func flagRecoveryImportNeeded() {
            UserDefaults.standard.set(true, forKey: LegacyRecipeStoreRecovery.needsRecoveryImportDefaultsKey)
        }

        // Primary store
        do {
            return try openContainer(at: primaryURL)
        } catch let primaryError {
            #if DEBUG
            print("SwiftData: primary store failed (\(primaryError)). Preserving file and trying recovery store.")
            #endif
            preserveStoreCopy(at: primaryURL, backupPrefix: "default.store.backup")
            flagRecoveryImportNeeded()

            do {
                return try openContainer(at: recoveryURL)
            } catch let recoveryError {
                #if DEBUG
                print("SwiftData: recovery store failed (\(recoveryError)). Creating fresh recovery store.")
                #endif
                preserveStoreCopy(at: recoveryURL, backupPrefix: "default.recovery.store.backup")
                archiveStoreFiles(at: recoveryURL, archivePrefix: "default.recovery.store.archived")
                flagRecoveryImportNeeded()

                do {
                    return try openContainer(at: recoveryURL)
                } catch let freshError {
                    fatalError(
                        "SwiftData: could not open any persistent store. "
                        + "Primary: \(primaryError), recovery: \(recoveryError), fresh: \(freshError)"
                    )
                }
            }
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            AppLifecycleRoot()
                .preferredColorScheme(.light)
                .font(AppTheme.libreBaskervilleFont(size: 17))
                .onOpenURL { url in
                                    GIDSignIn.sharedInstance.handle(url)
                                }
        }
        .modelContainer(sharedModelContainer)
    }
}

/// Hosts `MainView`, auth, and deep links.
private struct AppLifecycleRoot: View {
    @State private var authManager = AuthManager(service: SupabaseService.shared)

    var body: some View {
        MainView()
            .environment(authManager)
            .onOpenURL { url in
                Task {
                    await handleIncomingURL(url)
                }
            }
    }

    @MainActor
    private func handleIncomingURL(_ url: URL) async {
        // Supabase magic-link callback.
        if url.scheme == "io.supabase.user-management" {
            do {
                _ = try await SupabaseService.shared.client.auth.session(from: url)
                await authManager.getAuthState()
            } catch {
                print("Supabase magic link failed: \(error.localizedDescription)")
                authManager.error = error
            }
            return
        }
        

        guard url.scheme?.lowercased() == "airecipe" else { return }
        let host = url.host?.lowercased() ?? ""

        // Share extension: `airecipe://import` / `airecipe://open` (App Group or `?url=…`)
        if host == "import" || host == "open" {
            var link: String?
            var presentation = "sheet"
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
               let q = components.queryItems?.first(where: { $0.name == "url" })?.value {
                let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { link = t }
            }
            if link == nil, let handoff = PendingRecipeImport.takeImportHandoffFromAppGroupConsuming() {
                link = handoff.url
                presentation = handoff.presentation
            }
            guard let trimmed = link?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return }
            PendingRecipeImport.clearAppGroupPending()
            UserDefaults.standard.set(trimmed, forKey: PendingRecipeImport.userDefaultsKey)
            UserDefaults.standard.set(presentation, forKey: PendingRecipeImport.presentationModeKey)
            NotificationCenter.default.post(name: .importSharedRecipeLink, object: trimmed)
            return
        }

        if host == "photo-recipe" || host == "photorecipe" {
            PendingPhotoRecipeImport.markPending()
            NotificationCenter.default.post(name: .openPhotoRecipeImport, object: nil)
            return
        }

        // Settings / legal (e.g. RevenueCat paywall URL buttons)
        let route: String?
        switch host {
        case "settings": route = PendingAppDeepLink.settings
        case "terms": route = PendingAppDeepLink.terms
        case "privacy": route = PendingAppDeepLink.privacy
        default: route = nil
        }
        guard let route else { return }
        PendingAppDeepLink.store(route)
        NotificationCenter.default.post(name: .openAppDeepLink, object: route)
    }
}
