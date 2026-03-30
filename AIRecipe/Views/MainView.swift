import SwiftUI
import SwiftData
import StoreKit
import UIKit
import RevenueCat
import RevenueCatUI

/// Root view with iOS glass-style TabView: Home, Cook Book, Add, Meal Plan, Settings.
struct MainView: View {
    @State private var selectedTab: AppTab = .home
    @State private var addSheet: AddRecipeSheet?
    @State private var showAddMenu = false
    @Environment(AuthManager.self) private var authManager
    @AppStorage("hasOnboard") private var hasOnboard: Bool = false

    var body: some View {
        if hasOnboard{
            Group {
                content
            }
            .task {
                await authManager.getAuthState()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importSharedRecipeLink)) { note in
                guard let shared = note.object as? String else { return }
                let trimmed = shared.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                selectedTab = .home
                addSheet = .addLinkWithURLAutoProcess(trimmed)
            }
        } else{
            OnboardingView(isFinished: $hasOnboard)
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
        Group {
            switch selectedTab {
            case .home:
                RecipeListView(addSheet: $addSheet)
            case .cookbook:
                CookBookView()
            case .mealPlan:
                MealPlanView()
            case .settings:
                SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard)
        // Reserves space so lists/scroll views don’t sit under the tab bar; spacing clears the raised + button.
        .safeAreaInset(edge: .bottom, spacing: 48) {
            glassyTabBar
        }
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
    }
    
    var glassyTabBar: some View {
        HStack(spacing: 0) {
            // 左側按鈕
            tabButton(icon: "house.fill", title:"Home", tab: .home)
            tabButton(icon: "book.closed.fill", title:"Cook Book", tab: .cookbook)
            
            // --- 特大加號按鈕 ---
            Button {
                showAddMenu = true
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52) // 這裡就可以自由調整大小了！
                    .foregroundStyle(AppTheme.primary)
                    .background(Color.white, in: Circle()) // 背景光暈感
                    .shadow(color: AppTheme.primary.opacity(0.3), radius: 10, y: 5)
            }
            .offset(y: -10) // 讓按鈕往上飄出一點，更有層次感
            
            // 右側按鈕
            tabButton(icon: "calendar", title: "Meal Plan", tab: .mealPlan)
            tabButton(icon: "gearshape.fill", title: "Settings", tab: .settings)
        }
        .padding(.horizontal)
        .frame(height: 75)
        .background(
            Capsule() // 膠囊型狀玻璃質感
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.035), radius: 10, y: 5)
        )
        .padding(.horizontal, 20)
        // Sit close to the home indicator (low on screen); safeAreaInset already keeps content clear above.
        .padding(.bottom, 4)
    }

    private func tabButton(icon: String, title:String,tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4){
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selectedTab == tab ? AppTheme.primary : .gray)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selectedTab == tab ? AppTheme.primary : .gray)
                    .fontWeight(.semibold)
            }
            
        }
    }

}

enum AppTab {
    case home, cookbook, mealPlan, settings
}

struct CookBookView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 38))
                    .foregroundStyle(AppTheme.primary)
                Text("Cook Book")
                    .appFont(.title2)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Your saved cookbook collections will appear here.")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.surface.ignoresSafeArea())
            .navigationTitle("Cook Book")
        }
    }
}

struct SettingsView: View {
    @AppStorage("settings.language") private var language = "System"
    @AppStorage("settings.subscriptionTier") private var subscriptionTier = "Free"
    @AppStorage("settings.fontScale") private var fontScale: Double = 1.0
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPaywall = false
    @State private var legalDocument: LegalDocumentKind?
    @State private var showDeleteAccountConfirm = false
    @State private var deleteAccountError: String?
    @State private var isDeletingAccount = false
    @ObservedObject private var subManager = SubscriptionManager.shared
    
    private let languages: [String] = ["System", "English", "Mandarin", "Spanish", "Hindi", "Korean"]
    
    var body: some View {
        NavigationStack {
            List {
                Section("Recipe Settings"){
                    Picker("language", selection: $language) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    .padding(10)
                    .appFont(.body)
                    .boxStyle(cornerRadius: 5)
                    .pickerStyle(.navigationLink)
                }
                .listSectionSeparator(.hidden)
            
                Section("Subscription Plan"){
                    if subManager.isPremium {
                        Text("PREMIUM PLAN🔥")
                            .fontDesign(Font.Design.serif)
                            .font(Font.title)
                            .appFont(.body)
                            .listRowSeparator(.hidden)
                    } else {
                        Text("Free version")
                            .listRowSeparator(.hidden)
                    }
                    if subManager.isPremium {
                        Button("Change Your Plan") {
                            showPaywall = true
                        }
                        .listRowSeparator(.hidden)
                        .padding(10)
                        .appFont(.body)
                        .boxStyle(cornerRadius: 8)
                    } else {
                        Button("Upgrade to Premium") {
                            showPaywall = true
                        }
                        .listRowSeparator(.hidden)
                        .padding(10)
                        .appFont(.body)
                        .boxStyle(cornerRadius: 8)
                    }
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
                            await subManager.refreshAndSyncPlan()
                        }
                    }
                    .listRowSeparator(.hidden)
                    .padding(10)
                    .appFont(.body)
                    .boxStyle(cornerRadius: 8)
                }
                .listSectionSeparator(.hidden)
                .task {
                    await subManager.refreshAndSyncPlan()
                }

                Section("App Guidelines"){
                    Button {
                        legalDocument = .termsOfService
                    } label: {
                        Text("Terms of Service")
                            
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(AppTheme.textPrimary)
                            .appFont(.body)
                            .padding(10)
                            .boxStyle(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                    .frame(width:220)
                    .listRowSeparator(.hidden)

                    Button {
                        legalDocument = .privacyAndAI
                    } label: {
                        Text("Privacy & AI Policy")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(AppTheme.textPrimary)
                            .appFont(.body)
                            .padding(10)
                            .boxStyle(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                    .frame(width:220)
                    .listRowSeparator(.hidden)
                }
                Section("Contact support") {
                    NavigationLink {
                        GeneralQuestionsListView()
                    } label: {
                        Text("General Questions")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(AppTheme.textPrimary)
                            .appFont(.body)
                            .padding(10)
                            .boxStyle(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    
                    Button("Contact Me") {
                        openSupportEmail()
                    }
                    .listRowSeparator(.hidden)
                    .padding(10)
                    .appFont(.body)
                    .boxStyle(cornerRadius: 8)
                }
                .listSectionSeparator(.hidden)
                
                
                Section("Account") {
                    Button(role: .destructive) {
                        Task {
                            await authManager.signOut()
                        }
                    } label: {
                        HStack {
                            Text("Sign Out")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .appFont(.body)
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.red)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .frame(width: 150)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red, lineWidth: AppTheme.boxBorderWidth)
                    )
                    .padding(.trailing, AppTheme.boxShadowOffset)
                    .padding(.bottom, AppTheme.boxShadowOffset)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                    )

                    Button(role: .destructive) {
                        showDeleteAccountConfirm = true
                    } label: {
                        HStack {
                            Text("Delete account")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .appFont(.body)
                            Image(systemName: "trash.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.red)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .disabled(isDeletingAccount)
                    .frame(width: 180)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red, lineWidth: AppTheme.boxBorderWidth)
                    )
                    .padding(.trailing, AppTheme.boxShadowOffset)
                    .padding(.bottom, AppTheme.boxShadowOffset)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .listSectionSeparator(.hidden)
            .background(AppTheme.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .appFont(.largeTitle)
                        .fontDesign(.serif)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .sheet(item: $legalDocument) { kind in
                LegalDocumentReaderView(kind: kind)
            }
            .sheet(isPresented: $showPaywall) {
                RevenueCatUI.PaywallView(displayCloseButton: true)
                    .onPurchaseCompleted { _, _ in
                        Task { @MainActor in
                            await subManager.refreshAndSyncPlan()
                            subscriptionTier = subManager.isPremium ? "Pro" : "Free"
                        }
                    }
                    .onRestoreCompleted { _ in
                        Task { @MainActor in
                            await subManager.refreshAndSyncPlan()
                            subscriptionTier = subManager.isPremium ? "Pro" : "Free"
                        }
                    }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { @MainActor in
                    await subManager.refreshAndSyncPlan()
                    subscriptionTier = subManager.isPremium ? "Pro" : "Free"
                }
            }
            .confirmationDialog("Delete your account?", isPresented: $showDeleteAccountConfirm, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    Task { await performDeleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes your login and profile on our servers and deletes local recipes on this device. For manual cleanup in Supabase, see Supabase/delete_account.sql.")
            }
            .alert("Could not delete account", isPresented: Binding(
                get: { deleteAccountError != nil },
                set: { if !$0 { deleteAccountError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteAccountError ?? "")
            }
        }
    }

    @MainActor
    private func performDeleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await authManager.deleteAccount()
            try await Purchases.shared.logOut()
            try modelContext.delete(model: Recipe.self)
            try modelContext.delete(model: PlannedMeal.self)
            try modelContext.save()
            subscriptionTier = "Free"
            await subManager.checkStatus()
        } catch {
            deleteAccountError = error.localizedDescription
        }
    }

    private func openSubscriptionsInAppStore() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }

    private func openSupportEmail() {
        guard let url = URL(string: "mailto:bryanch@umich.edu") else { return }
        UIApplication.shared.open(url)
    }
}

private struct GeneralQuestionsListView: View {
    var body: some View {
        List {
            ForEach(SupportTopic.allCases) { topic in
                NavigationLink {
                    SupportTopicDetailView(topic: topic)
                } label: {
                    Text(topic.title)
                        .appFont(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(10)
                        .boxStyle(cornerRadius: 8)
                }
                .buttonStyle(.plain)
                .listRowBackground(AppTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.surface.ignoresSafeArea())
        .navigationTitle("General Questions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SupportTopicDetailView: View {
    let topic: SupportTopic

    var body: some View {
        ScrollView {
            Text(topic.instructions)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appFont(.body)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(14)
                .boxStyle(cornerRadius: 8)
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }
        .background(AppTheme.surface.ignoresSafeArea())
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum SupportTopic: String, CaseIterable, Identifiable {
    case uploadVideos
    case exportRecipes
    case deleteSubscription
    case manageMealPlan
    case createCookbook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uploadVideos: return "How to upload videos"
        case .exportRecipes: return "How to export"
        case .deleteSubscription: return "How to delete subscription"
        case .manageMealPlan: return "How to manage meal plan"
        case .createCookbook: return "How to create cookbook"
        }
    }

    var instructions: String {
        switch self {
        case .uploadVideos:
            return """
            1. Go to Home and tap the big + button.
            2. Select “Upload video link”.
            3. Paste a YouTube, Instagram, or TikTok URL.
            4. Confirm and wait for processing.
            5. Your recipe opens automatically when done.
            """
        case .exportRecipes:
            return """
            1. Open the recipe you want to export.
            2. Tap the Share/Export action in the recipe screen.
            3. Choose a format from the iOS share sheet.
            4. Save to Files, Notes, or share to another app.
            """
        case .deleteSubscription:
            return """
            1. Open Settings.
            2. Tap “Manage subscription”.
            3. You will be redirected to Apple subscription settings.
            4. Select this app subscription and cancel/modify your plan.
            """
        case .manageMealPlan:
            return """
            1. Open the Meal Plan tab.
            2. Use arrows to move between weeks.
            3. Tap a meal slot (breakfast/lunch/dinner).
            4. Choose a recipe from the picker.
            5. Use “Clear” in the picker to remove a planned meal.
            """
        case .createCookbook:
            return """
            1. Save recipes from the Home tab.
            2. Open the Cook Book tab to see your saved collection.
            3. Tap a recipe to review details and organize your planning.
            """
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
        .environment(AuthManager(service: SupabaseService()))
}
