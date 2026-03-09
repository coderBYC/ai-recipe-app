import SwiftUI
import SwiftData

/// Root view with iOS glass-style TabView: Home, Add, Settings.
struct MainView: View {
    @State private var selectedTab: AppTab = .home
    @State private var addSheet: AddRecipeSheet?
    @State private var showAddMenu = false

    var body: some View {
        TabView(selection: $selectedTab) {
            RecipeListView(addSheet: $addSheet)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppTab.home)

            addMenuTriggerView
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .tag(AppTab.add)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .confirmationDialog("Add Recipe", isPresented: $showAddMenu) {
            Button("Upload video link") {
                selectedTab = .home
                addSheet = .addLink
            }
            Button("Take photo") {
                selectedTab = .home
                addSheet = .takePhoto
            }
            Button("Manual recipe") {
                selectedTab = .home
                addSheet = .manualRecipe
            }
            Button("Cancel", role: .cancel) {
                selectedTab = .home
            }
        } message: {
            Text("Choose how to add a recipe")
        }
        .ignoresSafeArea(.keyboard)
    }

    /// Invisible view used as Add tab content; onAppear shows the add menu and then switches back to Home.
    private var addMenuTriggerView: some View {
        Color.clear
            .onAppear { showAddMenu = true }
    }
}

enum AppTab {
    case home, add, settings
}

// MARK: - Settings (placeholder)

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.surface.ignoresSafeArea()
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "gearshape.fill")
                        .font(.largeTitle)
                        .foregroundStyle(AppTheme.primary)
                    Text("Settings")
                        .appFont(.title2)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Coming soon")
                        .appFont(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .appFont(.largeTitle)
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
    }
}

#Preview("Main") {
    MainView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
