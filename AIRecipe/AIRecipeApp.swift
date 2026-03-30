import SwiftUI
import SwiftData
import Supabase
import RevenueCat

extension Notification.Name {
    static let importSharedRecipeLink = Notification.Name("importSharedRecipeLink")
}

@main
struct AIRecipeApp: App {
    @State private var authManager = AuthManager(service: SupabaseService())
    init (){
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: "appl_ZuccwFPnXxTruTqXcEEDVfrSopD")
    }
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Recipe.self, PlannedMeal.self])
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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

        // Share extension deep link: airecipe://import?url=<encoded>
        if url.scheme == "airecipe",
           url.host == "import",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let sharedURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
           !sharedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            NotificationCenter.default.post(name: .importSharedRecipeLink, object: sharedURL)
        }
    }
}
