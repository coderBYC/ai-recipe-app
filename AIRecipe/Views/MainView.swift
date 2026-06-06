import SwiftUI
import PostHog
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
    /// RevenueCat paywall presented from outside Settings (e.g. silent share import at free limit).
    @State private var showGlobalPaywall = false
    /// When set with Settings tab, `SettingsView` presents the matching legal sheet.
    @State private var deepLinkLegalDocument: LegalDocumentKind?
    @Environment(AuthManager.self) private var authManager
    /// Resolved after sign-in so Home / Meal Plan `@Query` scopes to this Supabase user only.
    @State private var signedInTabUserId: String = ""

    var body: some View {
        Group {
            content
        }
        .task {
            await authManager.getAuthState()
            if authManager.authState == .authenticated {
                await ShareExtensionQuotaSnapshot.refreshFromBackend()
            }
            consumePendingSharedRecipeURL()
            consumePendingDeepLink()
            consumePendingPhotoRecipeImport()
            if authManager.authState == .authenticated {
                await PhotoLibraryRecipeNotifier.shared.requestNeededPermissionsIfPossible()
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
        .onChange(of: authManager.authState) { _, newState in
            if newState != .authenticated {
                signedInTabUserId = ""
            }
            consumePendingSharedRecipeURL()
            consumePendingDeepLink()
            consumePendingPhotoRecipeImport()
            if newState == .authenticated {
                Task { await PhotoLibraryRecipeNotifier.shared.requestNeededPermissionsIfPossible() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, authManager.authState == .authenticated else { return }
            Task {
                await PhotoLibraryRecipeNotifier.shared.scanForRecentSavedVideosAndNotify()
            }
            consumePendingSharedRecipeURL()
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
            guard authManager.authState == .authenticated else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                showSavedVideoSuggestionBanner = true
            }
        }
    }

    /// Presents auto-processing sheet when a share/deep link stored URL is available and Home is reachable,
    /// or enqueues link import(s) in the background when the user queued from the share extension (`silent` queue).
    private func consumePendingSharedRecipeURL() {
        PendingRecipeImport.migratePendingFromAppGroupToStandardIfNeeded()
        guard authManager.authState == .authenticated else { return }

        let queued = (UserDefaults.standard.array(forKey: PendingRecipeImport.silentImportQueueKey) as? [String]) ?? []
        if !queued.isEmpty {
            UserDefaults.standard.removeObject(forKey: PendingRecipeImport.silentImportQueueKey)
            let container = modelContext.container
            Task { @MainActor in
                await SubscriptionManager.shared.checkStatus()
                var usedToday = 0
                if !SubscriptionManager.shared.isPremium,
                   let userId = await SupabaseService.shared.currentUserIdString() {
                    usedToday = (try? await FreeTierLimits.importsUsedToday(userId: userId)) ?? 0
                }
                for raw in queued {
                    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { continue }
                    let knownUsed = SubscriptionManager.shared.isPremium ? nil : usedToday
                    let enqueued = await RecipeImportProcessor.enqueueSharedLinkImportSilently(
                        url: t,
                        container: container,
                        knownImportsUsedToday: knownUsed,
                        presentPaywallOnLimit: false
                    )
                    if enqueued, !SubscriptionManager.shared.isPremium {
                        usedToday += 1
                    }
                }
            }
        }

        guard let raw = UserDefaults.standard.string(forKey: PendingRecipeImport.userDefaultsKey) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            UserDefaults.standard.removeObject(forKey: PendingRecipeImport.userDefaultsKey)
            UserDefaults.standard.removeObject(forKey: PendingRecipeImport.presentationModeKey)
            return
        }
        let modeRaw = UserDefaults.standard.string(forKey: PendingRecipeImport.presentationModeKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let silent = modeRaw == "silent"
        UserDefaults.standard.removeObject(forKey: PendingRecipeImport.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: PendingRecipeImport.presentationModeKey)

        if silent {
            Task { @MainActor in
                await RecipeImportProcessor.enqueueSharedLinkImportSilently(
                    url: trimmed,
                    container: modelContext.container,
                    presentPaywallOnLimit: false
                )
            }
            return
        }
        selectedTab = .home
        addSheet = .addLinkWithURLAutoProcess(trimmed)
    }

    /// Handles `airecipe://settings`, `airecipe://terms`, `airecipe://privacy` after sign-in.
    private func consumePendingDeepLink() {
        guard authManager.authState == .authenticated else { return }
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
        guard authManager.authState == .authenticated else { return }
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
            authenticatedTabRoot
        }
    }

    /// Waits for Supabase user id before showing tabs so SwiftData queries never mix accounts.
    private var authenticatedTabRoot: some View {
        Group {
            if signedInTabUserId.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await loadSignedInTabUserId() }
            } else {
                mainTabView
            }
        }
        .onChange(of: signedInTabUserId) { _, newId in
            guard !newId.isEmpty else { return }
            consumePendingSharedRecipeURL()
        }
    }

    @MainActor
    private func dismissAllImportSheets() {
        addSheet = nil
        showAddMenu = false
    }

    @MainActor
    private func loadSignedInTabUserId() async {
        guard let uid = await SupabaseService.shared.currentUserIdString(), !uid.isEmpty else { return }
        Recipe.migrateUnassignedOwnersOnce(modelContext: modelContext, assignedTo: uid)
        signedInTabUserId = uid
    }

    private var mainTabView: some View {
        ZStack(alignment: .top) {
            Group {
                switch selectedTab {
                case .home:
                    RecipeListView(filterOwnerId: signedInTabUserId, addSheet: $addSheet)
                case .cookbook:
                    ImportView()
                case .mealPlan:
                    MealPlanView(filterOwnerId: signedInTabUserId)
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
        .onChange(of: selectedTab) { _, tab in
            if tab == .cookbook {
                consumePendingSharedRecipeURL()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .presentRevenueCatPaywall)) { _ in
            showGlobalPaywall = true
        }
        .sheet(isPresented: $showGlobalPaywall, onDismiss: dismissAllImportSheets) {
            RevenueCatUI.PaywallView(displayCloseButton: true)
                .onRequestedDismissal {
                    showGlobalPaywall = false
                    dismissAllImportSheets()
                }
                .onPurchaseCompleted { _, _ in
                    Task { @MainActor in
                        await SubscriptionManager.shared.refreshAndSyncPlan()
                        await ShareExtensionQuotaSnapshot.refreshFromBackend()
                        showGlobalPaywall = false
                        dismissAllImportSheets()
                    }
                }
                .onRestoreCompleted { _ in
                    Task { @MainActor in
                        await SubscriptionManager.shared.refreshAndSyncPlan()
                        await ShareExtensionQuotaSnapshot.refreshFromBackend()
                        showGlobalPaywall = false
                        dismissAllImportSheets()
                    }
                }
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
                    .font(AppTheme.bitterFont(size: 22, weight: .ultraLight))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selectedTab == tab ? AppTheme.primary : .gray)
                Text(title)
                    .font(AppTheme.nanumMyeongjoFont(size: 10, weight: .medium))
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
                PostHogSDK.shared.capture("ai_recipe_added", properties: [
                        "meal_type": "dinner"
                ])
                print("🚀 PostHog successfully initialized via AppDelegate!")
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
                        Text("Links you share from Instagram, YouTube, or TikTok appear here after you close the share sheet — open the app to finish processing.")
                            .appFont(.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.surface.ignoresSafeArea())
                } else {
                    List {
                        ForEach(submissions.indices, id: \.self) { index in
                            importRowView(submissions[index], index: index)
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
                        .nanumAppFont(.largeTitle)
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

    private func importRowView(_ submission: RecipeImportSubmission, index: Int) -> some View {
        ImportSubmissionRow(
            submission: submission,
            onReadyRowTap: readyTapAction(for: submission)
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

    private func readyTapAction(for submission: RecipeImportSubmission) -> (() -> Void)? {
        guard submission.status == .ready else { return nil }
        return {
            importReview = ImportReviewItem(submission: submission)
        }
    }
}

private struct ImportSubmissionRow: View {
    @Environment(\.modelContext) private var modelContext
    let submission: RecipeImportSubmission
    var onReadyRowTap: (() -> Void)?

    private var displayTitle: String {
        let title = submission.readyTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let url = submission.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty { return "Importing recipe…" }
        if let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") {
            return host
        }
        return url
    }

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
                        Text(displayTitle)
                            .appFont(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                        Text(submission.status == .processing ? "Processing…" : (submission.errorMessage.isEmpty ? "Failed" : submission.errorMessage))
                            .appFont(.caption)
                            .foregroundStyle(submission.status == .failed ? Color.red : AppTheme.textSecondary)
                            .lineLimit(submission.status == .failed ? 4 : 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ImportSubmissionThumbnailView(submission: submission)

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

private enum SettingsLayout {
    /// Space between section groups.
    static let sectionSpacing: CGFloat = 40
    /// Space between rows inside a section.
    static let rowSpacing: CGFloat = 6
    static let rowInsets = EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20)
}

private extension View {
    func settingsListRow() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(SettingsLayout.rowInsets)
            .listRowBackground(Color.clear)
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
    @State private var freeDailyImportUsed = 0
    @State private var isLoadingFreeUsage = false
    @ObservedObject private var subManager = SubscriptionManager.shared

    private var freeDailyImportRemaining: Int {
        FreeTierLimits.remainingToday(usedToday: freeDailyImportUsed)
    }

    private var freeDailyUsageRate: Double {
        guard FreeTierLimits.dailyImportLimit > 0 else { return 0 }
        return min(1, max(0, Double(freeDailyImportUsed) / Double(FreeTierLimits.dailyImportLimit)))
    }

    private var freeUsageRingColor: Color {
        freeDailyUsageRate >= 0.8 ? .red : .green
    }

    
    private let languages: [String] = ["System", "English", "Mandarin", "Spanish", "Hindi", "Korean"]
    
    var body: some View {
        NavigationStack {
            List{
                Section("Recipe Settings"){
                    Picker("language", selection: $language) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    .padding(10)
                    .bitterAppFont(.body)
                    .boxStyle(cornerRadius: 8)
                    .pickerStyle(.navigationLink)
                    .frame(maxWidth:.infinity, alignment: .init(horizontal: .center, vertical: .center))
                    .settingsListRow()
                }

                Section("Subscription Plan"){
                    if subManager.isPremium {
                        Text("PREMIUM PLAN🔥")
                            .bitterAppFont(.body)
                            .settingsListRow()
                    } else {
                        Text("Free Version")
                            .settingsListRow()
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .stroke(AppTheme.textSecondary.opacity(0.2), lineWidth: 11)
                                Circle()
                                    .trim(from: 0, to: freeDailyUsageRate)
                                    .stroke(
                                        freeUsageRingColor,
                                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 2) {
                                    if isLoadingFreeUsage {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("\(freeDailyImportRemaining)")
                                            .bitterAppFont(.titleBold)
                                            .foregroundStyle(AppTheme.textPrimary)
                                        Text("imports left")
                                            .bitterAppFont(.caption)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                }
                            }
                            .frame(width: 120, height: 120)
                        }
                        .padding(.vertical, 2)
                        .settingsListRow()
                    }
                    if subManager.isPremium {
                        Button("Change Your Plan") {
                            showPaywall = true
                        }
                        .settingsListRow()
                        .padding(10)
                        .bitterAppFont(.body)
                        .boxStyle(cornerRadius: 8)
                    } else {
                        Button("Upgrade to Premium") {
                            showPaywall = true
                        }
                        .settingsListRow()
                        .padding(10)
                        .bitterAppFont(.body)
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
                    .settingsListRow()
                    .padding(10)
                    .bitterAppFont(.body)
                    .boxStyle(cornerRadius: 8)
                }
                .listSectionSeparator(.hidden)
                .task {
                    await subManager.refreshAndSyncPlan()
                    await refreshFreeDailyImportUsage()
                }

                Section("App Guidelines"){
                    Button {
                        legalDocument = .termsOfService
                    } label: {
                        Text("Terms of Service")
                            .frame(alignment: .center)
                            .foregroundStyle(AppTheme.textPrimary)
                            .bitterAppFont(.body)
                            .padding(10)
                            .boxStyle(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                   
                    .settingsListRow()

                    Button {
                        legalDocument = .privacyAndAI
                    } label: {
                        Text("Privacy & AI Policy")
                            .frame(alignment: .center)
                            .foregroundStyle(AppTheme.textPrimary)
                            .bitterAppFont(.body)
                            .padding(10)
                            .boxStyle(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                   
                    .settingsListRow()
                }
                .listSectionSeparator(.hidden)

                Section("Contact support") {
                    Button {
                        GeneralQuestionsListView()
                    } label: {
                        Text("General Questions")
                            
                            .foregroundStyle(AppTheme.textPrimary)
                            .bitterAppFont(.body)
                            .padding(10)
                            .boxStyle(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                    .settingsListRow()

                    Button {
                        requestAppStoreReview()
                    } label: {
                        Text("Rate Us")
                           
                            .foregroundStyle(AppTheme.textPrimary)
                            .bitterAppFont(.body)
                            .padding(10)
                            .boxStyle(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                    .settingsListRow()

                    Button("Contact Me") {
                        openSupportEmail()
                    }
                    .settingsListRow()
                    .padding(10)
                    .bitterAppFont(.body)
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
                                .frame(alignment: .center)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 10)
                                
                                .bitterAppFont(.body)
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(AppTheme.bitterFont(size: 18, weight: .semibold))
                                .foregroundStyle(Color.red)
                        }
                    }
                    .settingsListRow()
                    .frame(width: 110)
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
                                .frame(alignment: .center)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 10)
                                .bitterAppFont(.body)
                            Image(systemName: "trash.fill")
                                .font(AppTheme.bitterFont(size: 18, weight: .semibold))
                                .foregroundStyle(Color.red)
                        }
                    }
                    .frame(width: 150)
                    .settingsListRow()
                    .disabled(isDeletingAccount)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red, lineWidth: AppTheme.boxBorderWidth)
                    )
                    .padding(.trailing, AppTheme.boxShadowOffset)
                    .padding(.bottom, AppTheme.boxShadowOffset)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red)
                    )
                }
                
                .listSectionSeparator(.hidden)
            }
            .listSectionSpacing(SettingsLayout.sectionSpacing)
            .listRowSpacing(SettingsLayout.rowSpacing)
            .environment(\.defaultMinListRowHeight, 8)
            .scrollContentBackground(.hidden)
            .listSectionSeparator(.hidden)
            .background(AppTheme.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .nanumAppFont(.largeTitle)
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
            .bitterAppFont(.titleBold)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { @MainActor in
                    await subManager.refreshAndSyncPlan()
                    subscriptionTier = subManager.isPremium ? "Pro" : "Free"
                    await refreshFreeDailyImportUsage()
                }
            }
            .alert("Delete your account?", isPresented: $showDeleteAccountConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete account", role: .destructive) {
                    Task { await performDeleteAccount() }
                }
            } message: {
                Text("This permanently deletes your login account. Local recipes on this device will also be removed.")
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

    @MainActor
    private func requestAppStoreReview() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
        #endif
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return }
        AppStore.requestReview(in: scene)
    }

    @MainActor
    private func refreshFreeDailyImportUsage() async {
        guard !subManager.isPremium else {
            freeDailyImportUsed = 0
            isLoadingFreeUsage = false
            return
        }
        guard !isLoadingFreeUsage else { return }

        isLoadingFreeUsage = true
        defer { isLoadingFreeUsage = false }

        guard let userId = await SupabaseService.shared.currentUserIdString(), !userId.isEmpty else {
            freeDailyImportUsed = 0
            return
        }

        do {
            let usedToday = try await FreeTierLimits.importsUsedToday(userId: userId)
            freeDailyImportUsed = min(FreeTierLimits.dailyImportLimit, usedToday)
            ShareExtensionQuotaSnapshot.publish(
                usedToday: freeDailyImportUsed,
                isPremium: subManager.isPremium
            )
        } catch {
            freeDailyImportUsed = 0
        }
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
                        .bitterAppFont(.body)
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
                .bitterAppFont(.body)
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



#Preview("Settings") {
    SettingsView(deepLinkLegalDocument: .constant(nil))
        .modelContainer(for: [Recipe.self, PlannedMeal.self], inMemory: true)
        .environment(AuthManager(service: SupabaseService()))
}
