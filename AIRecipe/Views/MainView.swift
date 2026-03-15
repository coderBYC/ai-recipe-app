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
            ///Button("Take photo") {
            ///    selectedTab = .home
            ///    addSheet = .takePhoto
            ///}
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

struct SettingsView: View {
    @AppStorage("settings.language") private var language = "System"
    @AppStorage("settings.subscriptionTier") private var subscriptionTier = "Free"
    @AppStorage("settings.fontScale") private var fontScale: Double = 1.0

    private let languages = ["System", "English", "Mandarin", "Spanish", "Hindi", "Korean"]
    private let tiers = ["Free", "Pro Monthly", "Pro Yearly"]

    var body: some View {
        NavigationStack {
            List {
                Section("Language") {
                    Picker("App language", selection: $language) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Text("Current: \(language)")
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Section("Subscription") {
                    Picker("Plan", selection: $subscriptionTier) {
                        ForEach(tiers, id: \.self) { tier in
                            Text(tier).tag(tier)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Text("Use this plan to control AI usage and export limits.")
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Recipe font size") {
                    HStack {
                        Text("Font size")
                            .appFont(.body)
                        Spacer()
                        Text(String(format: "%.1fx", fontScale))
                            .appFont(.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Slider(value: $fontScale, in: 0.8...1.4, step: 0.1)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.surface.ignoresSafeArea())
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

enum AppLanguage: String {
    case system = "System"
    case english = "English"
    case chinese = "Chinese"
    case spanish = "Spanish"
    case hindi = "Hindi"
    case korean = "Korean"

    var backendCode: String {
        switch self {
        case .system, .english: return "en"
        case .chinese: return "zh"
        case .spanish: return "es"
        case .hindi: return "hi"
        case .korean: return "ko"
        }
    }
}

#Preview("Main") {
    MainView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
