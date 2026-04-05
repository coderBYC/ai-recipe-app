import SwiftUI
import SwiftData
import Supabase
import RevenueCat

extension Notification.Name {
    static let importSharedRecipeLink = Notification.Name("importSharedRecipeLink")
    /// Posted after `PendingAppDeepLink.store` when handling `airecipe://settings|terms|privacy`.
    static let openAppDeepLink = Notification.Name("openAppDeepLink")
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

    private static var groupDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupSuiteName)
    }

    /// If the extension couldn’t open the app, migrate the pending URL when the user opens the app manually.
    static func migratePendingFromAppGroupToStandardIfNeeded() {
        if let existing = UserDefaults.standard.string(forKey: userDefaultsKey),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        guard let raw = groupDefaults?.string(forKey: userDefaultsKey),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
        groupDefaults?.removeObject(forKey: userDefaultsKey)
    }

    static func takePendingURLFromAppGroupConsuming() -> String? {
        guard let raw = groupDefaults?.string(forKey: userDefaultsKey) else { return nil }
        groupDefaults?.removeObject(forKey: userDefaultsKey)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func clearAppGroupPending() {
        groupDefaults?.removeObject(forKey: userDefaultsKey)
    }
}

@main
struct AIRecipeApp: App {
    @State private var authManager = AuthManager(service: SupabaseService())
    init() {
        Purchases.logLevel = .debug
        let rcKey = AppSecrets.revenueCatPublicKey
        guard !rcKey.isEmpty else {
            fatalError(AppSecrets.configurationHint)
        }
        Purchases.configure(withAPIKey: rcKey)
    }
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Recipe.self, PlannedMeal.self])
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("SwiftData: could not resolve application support directory.")
        }
        let storeURL = appSupport.appending(path: "default.store")
        let config = ModelConfiguration(isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            #if DEBUG
            print("SwiftData: Failed to load store (\(error)). Removing old store and retrying (schema may have changed).")
            #endif
            let storeDir = storeURL.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeDir.appending(path: "default.store-wal"))
            try? FileManager.default.removeItem(at: storeDir.appending(path: "default.store-shm"))
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                return container
            }
            return (try? ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))
                ?? (try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.light)
                .environment(authManager)
                .onOpenURL { url in
                    Task {
                        await handleIncomingURL(url)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    @MainActor
    private func handleIncomingURL(_ url: URL) async {
        // Supabase magic-link callback.
        if url.scheme == "io.supabase.user-management" {
            try? await SupabaseService.shared.client.auth.session(from: url)
            return
        }

        guard url.scheme?.lowercased() == "airecipe" else { return }
        let host = url.host?.lowercased() ?? ""

        // Share extension: `airecipe://import` / `airecipe://open` (App Group or `?url=…`)
        if host == "import" || host == "open" {
            var link: String?
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
               let q = components.queryItems?.first(where: { $0.name == "url" })?.value {
                let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { link = t }
            }
            if link == nil {
                link = PendingRecipeImport.takePendingURLFromAppGroupConsuming()
            }
            guard let trimmed = link?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return }
            PendingRecipeImport.clearAppGroupPending()
            UserDefaults.standard.set(trimmed, forKey: PendingRecipeImport.userDefaultsKey)
            NotificationCenter.default.post(name: .importSharedRecipeLink, object: trimmed)
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
