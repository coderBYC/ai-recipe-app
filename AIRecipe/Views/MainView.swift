import SwiftUI
import SwiftData
import StoreKit
import UIKit

/// Root view with iOS glass-style TabView: Home, Add, Settings.
struct MainView: View {
    @State private var selectedTab: AppTab = .home
    @State private var addSheet: AddRecipeSheet?
    @State private var showAddMenu = false
    @Environment(AuthManager.self) private var authManager
    
    var body: some View {
        Group {
            content
        }
        .task {
            await authManager.getAuthState()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch authManager.authState {
        case .notDetermined:
            ProgressView()
        case .notAuthenticated:
            LoginView(onSignedIn: { _ in }, onError: { _ in })
        case .authenticated:
            mainTabView
        }
    }

    private var mainTabView: some View {
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
    @Environment(AuthManager.self) private var authManager
    @State private var showPaywall = false
    private let languages = ["System", "English", "Mandarin", "Spanish", "Hindi", "Korean"]

    var body: some View {
        NavigationStack {
            List {
                Section("Recipe Language") {
                    Picker("language", selection: $language) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    .padding(10)
                    .boxStyle(cornerRadius: 5)
                    .pickerStyle(.navigationLink)
                }

                Section("Subscription") {
                    Button("\(subscriptionTier)") {
                        showPaywall = true
                    }
                    .padding(10)
                    .boxStyle(cornerRadius: 5)

                    Button("Manage subscription") {
                        Task { @MainActor in
                            if let scene = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first {
                                do {
                                    try await AppStore.showManageSubscriptions(in: scene)
                                } catch {
                                    openSubscriptionsInAppStore()
                                }
                            } else {
                                openSubscriptionsInAppStore()
                            }
                        }
                    }
                    .padding(10)
                    .boxStyle(cornerRadius: 5)

                    Text("Cancel or change your plan in the App Store. Apple does not allow canceling inside the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Account") {
                    Button(role: .destructive) {
                        Task {
                            await authManager.signOut()
                        }
                    } label: {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .boxStyle(cornerRadius: 5)
                    }
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
            .sheet(isPresented: $showPaywall) {
                PaywallView(onPlanUpdated: { plan in
                    subscriptionTier = plan
                    Task {
                        try? await SupabaseService.shared.updatePlan(to: plan)
                    }
                })
            }
        }
    }

    private func openSubscriptionsInAppStore() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
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
        .environment(AuthManager(service: SupabaseService()))
}
