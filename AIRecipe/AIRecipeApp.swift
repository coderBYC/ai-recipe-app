import SwiftUI
import SwiftData
import Supabase

@main
struct AIRecipeApp: App {
    @State private var authManager = AuthManager(service: SupabaseService())
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Recipe.self])
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
        }
        .modelContainer(sharedModelContainer)
    }
}
