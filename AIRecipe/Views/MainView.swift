import SwiftUI
import SwiftData
import StoreKit
import UIKit
import RevenueCatUI

/// Root view with iOS glass-style TabView: Home, Cook Book, Add, Meal Plan, Settings.
struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppTab = .home
    @State private var addSheet: AddRecipeSheet?
    @State private var showAddMenu = false
    @State private var showSavedVideoSuggestionBanner = false
    /// When set with Settings tab, `SettingsView` presents the matching legal sheet.
    @State private var deepLinkLegalDocument: LegalDocumentKind?
    @Environment(AuthManager.self) private var authManager
    @AppStorage("hasOnboard") private var hasOnboard: Bool = false

    var body: some View {
        Group {
            if hasOnboard {
                Group {
                    content
                }
                .task {
                    await authManager.getAuthState()
                    consumePendingSharedRecipeURL()
                    consumePendingDeepLink()
                    consumePendingPhotoRecipeImport()
                    if authManager.authState == .authenticated {
                        await PhotoLibraryRecipeNotifier.shared.requestNeededPermissionsIfPossible()
                    }
                }
            } else {
                OnboardingView(isFinished: $hasOnboard)
            }
        }
        .onAppear {
            Task { @MainActor in
                consumePendingSharedRecipeURL()
                consumePendingDeepLink()
                consumePendingPhotoRecipeImport()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importSharedRecipeLink)) { _ in
            consumePendingSharedRecipeURL()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAppDeepLink)) { _ in
            consumePendingDeepLink()
        }
        .onChange(of: hasOnboard) { _, _ in
            consumePendingSharedRecipeURL()
            consumePendingDeepLink()
            consumePendingPhotoRecipeImport()
        }
        .onChange(of: authManager.authState) { _, newState in
            consumePendingSharedRecipeURL()
            consumePendingDeepLink()
            consumePendingPhotoRecipeImport()
            if newState == .authenticated {
                Task { await PhotoLibraryRecipeNotifier.shared.requestNeededPermissionsIfPossible() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, hasOnboard, authManager.authState == .authenticated else { return }
            Task {
                await PhotoLibraryRecipeNotifier.shared.scanForRecentSavedVideosAndNotify()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                try? modelContext.save()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPhotoRecipeImport)) { _ in
            consumePendingPhotoRecipeImport()
        }
        .onReceive(NotificationCenter.default.publisher(for: .savedVideoRecipeSuggestion)) { _ in
            guard hasOnboard, authManager.authState == .authenticated else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                showSavedVideoSuggestionBanner = true
            }
        }
    }

    /// Presents auto-processing sheet when a share/deep link stored URL is available and Home is reachable.
    private func consumePendingSharedRecipeURL() {
        PendingRecipeImport.migratePendingFromAppGroupToStandardIfNeeded()
        guard hasOnboard, authManager.authState == .authenticated else { return }
        guard let raw = UserDefaults.standard.string(forKey: PendingRecipeImport.userDefaultsKey) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            UserDefaults.standard.removeObject(forKey: PendingRecipeImport.userDefaultsKey)
            return
        }
        UserDefaults.standard.removeObject(forKey: PendingRecipeImport.userDefaultsKey)
        selectedTab = .home
        addSheet = .addLinkWithURLAutoProcess(trimmed)
    }

    /// Handles `airecipe://settings`, `airecipe://terms`, `airecipe://privacy` after onboard + sign-in.
    private func consumePendingDeepLink() {
        guard hasOnboard, authManager.authState == .authenticated else { return }
        guard let route = PendingAppDeepLink.consume() else { return }
        switch route {
        case PendingAppDeepLink.settings:
            selectedTab = .settings
        case PendingAppDeepLink.terms:
            selectedTab = .settings
            deepLinkLegalDocument = .termsOfService
        case PendingAppDeepLink.privacy:
            selectedTab = .settings
            deepLinkLegalDocument = .privacyAndAI
        default:
            break
        }
    }

    /// Opens the Photos video import sheet after a notification tap or `airecipe://photo-recipe`.
    private func consumePendingPhotoRecipeImport() {
        guard hasOnboard, authManager.authState == .authenticated else { return }
        guard PendingPhotoRecipeImport.takePending() else { return }
        selectedTab = .home
        addSheet = .photoLibraryVideo
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
        ZStack(alignment: .top) {
            Group {
                switch selectedTab {
                case .home:
                    RecipeListView(addSheet: $addSheet)
                case .cookbook:
                    ImportView()
                case .mealPlan:
                    MealPlanView()
                case .settings:
                    SettingsView(deepLinkLegalDocument: $deepLinkLegalDocument)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showSavedVideoSuggestionBanner {
                savedVideoSuggestionBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        // Reserves space so lists/scroll views don’t sit under the tab bar; spacing clears the raised + button.
        .safeAreaInset(edge: .bottom, spacing: 48) {
            glassyTabBar
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToImportsTab)) { _ in
            selectedTab = .cookbook
        }
        .confirmationDialog("Add Recipe", isPresented: $showAddMenu) {
            Button("Upload video link") {
                selectedTab = .home
                addSheet = .addLink
            }
            Button("Video from Photos") {
                selectedTab = .home
                addSheet = .photoLibraryVideo
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

    private var savedVideoSuggestionBanner: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                showSavedVideoSuggestionBanner = false
                selectedTab = .home
                addSheet = .photoLibraryVideo
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wanna Build Recipe?")
                            .appFont(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Pick a video you saved to Photos and turn it into a recipe.")
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(AppTheme.bitterFont(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                }
                .padding(14)
                .padding(.trailing, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showSavedVideoSuggestionBanner = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppTheme.bitterFont(size: 20, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(6)
            .buttonStyle(.plain)
        }
    }
    
    var glassyTabBar: some View {
        HStack(spacing: 0) {
            // 左側按鈕
            tabButton(icon: "house.fill", title:"Home", tab: .home)
            tabButton(icon: "square.and.arrow.up", title:"Imports", tab: .cookbook)
            
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
                    .font(AppTheme.bitterFont(size: 22, weight: .regular))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selectedTab == tab ? AppTheme.primary : .gray)
                Text(title)
                    .font(AppTheme.bitterFont(size: 10, weight: .medium))
                    .foregroundStyle(selectedTab == tab ? AppTheme.primary : .gray)
                    .fontWeight(.semibold)
            }
            
        }
    }

}

enum AppTab {
    case home, cookbook, mealPlan, settings
}

struct ImportReviewItem: Identifiable {
    var id: UUID { submission.id }
    let submission: RecipeImportSubmission
}

/// Full recipe detail from an in-memory `Recipe` (same UI as Home); user adds to library or discards the import.
struct ImportRecipeReviewSheet: View {
    @Environment(\.modelContext) private var mainModelContext
    let submission: RecipeImportSubmission
    let onDismiss: () -> Void
    /// Called with the persisted `Recipe` after the user taps **Add to Home** (optional).
    var onAddedToHome: ((Recipe) -> Void)? = nil

    @State private var previewContainer: ModelContainer?
    @State private var previewRecipe: Recipe?
    @State private var previewLoadFailed = false

    var body: some View {
        Group {
            if let previewContainer, let previewRecipe {
                RecipePageView(recipe: previewRecipe, onDismiss: onDismiss)
                    .modelContainer(previewContainer)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        reviewActionsBar
                    }
            } else if previewLoadFailed {
                VStack(spacing: 16) {
                    Text("Couldn’t load preview.")
                        .appFont(.headline)
                    Button("Close") { onDismiss() }
                        .appFont(.body)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.surface)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading preview…")
                        .appFont(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.surface)
            }
        }
        .task { await loadPreview() }
    }

    private var reviewActionsBar: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                RecipeImportProcessor.removePendingVideoIfAny(relPath: submission.pendingVideoRelPath)
                mainModelContext.delete(submission)
                try? mainModelContext.save()
                onDismiss()
            } label: {
                Text("Discard")
                    .frame(maxWidth: .infinity)
                    .appFont(.headline)
            }
            .buttonStyle(.bordered)

            Button {
                let recipe = RecipeImportProcessor.approveSubmission(submission, modelContext: mainModelContext)
                onAddedToHome?(recipe)
                onDismiss()
            } label: {
                Text("Add to Home")
                    .frame(maxWidth: .infinity)
                    .appFont(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.shadow)
                .frame(height: 1)
        }
    }

    @MainActor
    private func loadPreview() async {
        guard previewContainer == nil else { return }
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: Recipe.self, configurations: config)
            let ctx = ModelContext(container)
            let recipe = RecipeImportProcessor.makeRecipe(from: submission)
            ctx.insert(recipe)
            try ctx.save()
            previewContainer = container
            previewRecipe = recipe
        } catch {
            previewContainer = nil
            previewRecipe = nil
            previewLoadFailed = true
        }
    }
}

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecipeImportSubmission.createdAt, order: .reverse) private var submissions: [RecipeImportSubmission]
    @State private var importReview: ImportReviewItem?
    /// Optional hook when user completes **Add to Home** from the import preview (e.g. onboarding).
    var onTutorialAddedRecipe: ((Recipe) -> Void)? = nil
    @State private var forcePollTick: Int = 0

    private var hasProcessingRows: Bool {
        submissions.contains { $0.status == .processing && $0.importKind == "link" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if submissions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                            .font(AppTheme.bitterFont(size: 38, weight: .regular))
                            .foregroundStyle(AppTheme.primary)
                        Text("My Imports")
                            .appFont(.title2)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Add a link or video from Home — progress shows here.")
                            .appFont(.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.surface.ignoresSafeArea())
                } else {
                    List {
                        ForEach(submissions) { submission in
                            ImportSubmissionRow(
                                submission: submission,
                                onReadyRowTap: submission.status == .ready
                                    ? { importReview = ImportReviewItem(submission: submission) }
                                    : nil
                            )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteSubmission(submission)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.surface.ignoresSafeArea())
                }
            }
            .navigationTitle("Imports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Imports")
                        .appFont(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .sheet(item: $importReview) { item in
                ImportRecipeReviewSheet(
                    submission: item.submission,
                    onDismiss: { importReview = nil },
                    onAddedToHome: onTutorialAddedRecipe
                )
            }
            .task {
                await RecipeImportProcessor.syncRemoteLinkJobs(container: modelContext.container)
            }
            .task(id: hasProcessingRows ? forcePollTick : -1) {
                guard hasProcessingRows else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await RecipeImportProcessor.syncRemoteLinkJobs(container: modelContext.container)
                    if !hasProcessingRows { break }
                }
            }
            .refreshable {
                await RecipeImportProcessor.syncRemoteLinkJobs(container: modelContext.container)
            }
        }
    }

    private func deleteSubmission(_ submission: RecipeImportSubmission) {
        RecipeImportProcessor.removePendingVideoIfAny(relPath: submission.pendingVideoRelPath)
        modelContext.delete(submission)
        try? modelContext.save()
        forcePollTick += 1
    }
}

private struct ImportSubmissionRow: View {
    @Environment(\.modelContext) private var modelContext
    let submission: RecipeImportSubmission
    var onReadyRowTap: (() -> Void)?

    var body: some View {
        Group {
            switch submission.status {
            case .ready:
                RecipeRowView(recipe: RecipeImportProcessor.makeRecipe(from: submission))
                    .onTapGesture { onReadyRowTap?() }
                    .contextMenu {
                        Button(role: .destructive) {
                            RecipeImportProcessor.removePendingVideoIfAny(relPath: submission.pendingVideoRelPath)
                            modelContext.delete(submission)
                            try? modelContext.save()
                        } label: {
                            Label("Delete import", systemImage: "trash")
                        }
                    }
            case .processing, .failed:
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(submission.sourceURL)
                            .appFont(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                        Text(submission.status == .processing ? "Processing…" : (submission.errorMessage.isEmpty ? "Failed" : submission.errorMessage))
                            .appFont(.caption)
                            .foregroundStyle(submission.status == .failed ? Color.red : AppTheme.textSecondary)
                            .lineLimit(submission.status == .failed ? 4 : 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if submission.status == .processing {
                        ProgressView()
                            .tint(AppTheme.primary)
                    }
                }
                .padding(14)
                .boxStyle(cornerRadius: 10)
            }
        }
    }
}

struct SettingsView: View {
    @Binding var deepLinkLegalDocument: LegalDocumentKind?
    @AppStorage("settings.language") private var language = "System"
    @AppStorage("settings.subscriptionTier") private var subscriptionTier = "Free"
    @AppStorage("settings.fontScale") private var fontScale: Double = 1.0
    @Environment(AuthManager.self) private var authManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPaywall = false
    @State private var legalDocument: LegalDocumentKind?

    init(deepLinkLegalDocument: Binding<LegalDocumentKind?> = .constant(nil)) {
        _deepLinkLegalDocument = deepLinkLegalDocument
    }
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
                                .font(AppTheme.bitterFont(size: 18, weight: .semibold))
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
                                .font(AppTheme.bitterFont(size: 18, weight: .semibold))
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
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .sheet(item: $legalDocument) { kind in
                LegalDocumentReaderView(kind: kind)
            }
            .onAppear { syncDeepLinkLegalIfNeeded() }
            .onChange(of: deepLinkLegalDocument) { _, _ in
                syncDeepLinkLegalIfNeeded()
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
            .appFont(.titleBold)
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
            .errorPopup(message: $deleteAccountError)
        }
    }

    private func syncDeepLinkLegalIfNeeded() {
        guard let kind = deepLinkLegalDocument else { return }
        legalDocument = kind
        deepLinkLegalDocument = nil
    }

    @MainActor
    private func performDeleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await authManager.deleteAccount()
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
