import SwiftUI
import SwiftData
import StoreKit
import UIKit
import PostHog

struct ImportReviewActions {
    let cookbooks: [Cookbook]
    let onDiscard: () -> Void
    let onAddToCookbook: (String) -> Void
}

struct RecipePageView: View {
    @Environment(\.modelContext) private var modelContext
  
    @AppStorage("settings.fontScale") private var fontScale: Double = 1.0
    @Bindable var recipe: Recipe
    var onDismiss: () -> Void
    var openEditOnAppear: Bool = false
    var importReviewActions: ImportReviewActions? = nil
    /// After bookmarking, dismiss and open Home bookmarks sheet.
    var onBookmarkNavigate: (() -> Void)? = nil
    @ObservedObject private var subManager = SubscriptionManager.shared

    @AppStorage("app.didRequestStoreReviewAfterFirstGeneratedRecipe") private var didRequestStoreReviewAfterFirstGeneratedRecipe = false

    @State private var showingEdit = false
    @State private var showingImport = false
    @State private var showCookMode = false
    @State private var showShareTextSheet = false
    @State private var showPDFPreview = false
    @State private var pdfPreviewHTML = ""
    @State private var exportedPDFURL: URL?
    @State private var isExportingPDF = false
    @State private var exportError: String?
    @State private var displayServings: Int = 1

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.surface
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerRow
                        if shouldShowVideoPreview {
                            videoSection
                        }
                        estimateTimeSection
                        ingredientsSection
                        stepsSection
                        NoteSection
                        if subManager.isPremium, recipe.hasNutrition {
                            nutritionSection
                        }
                        ratingSection
                        if !recipe.sourceURL.isEmpty {
                            openLinkSection
                        }
                        
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .appFont(.callout)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                if let importReviewActions {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            importReviewActions.onDiscard()
                        } label: {
                            Image(systemName: "trash")
                                .appFont(.callout)
                        }

                        Menu {
                            ForEach(importReviewActions.cookbooks) { book in
                                Button(book.name.isEmpty ? CookbookService.defaultCookbookName : book.name) {
                                    importReviewActions.onAddToCookbook(book.id)
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                                .appFont(.callout)
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }
                } else {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            handleBookmarkTap()
                        } label: {
                            Image(systemName: recipe.isBookmarked ? "bookmark.fill" : "bookmark")
                                .appFont(.callout)
                                .foregroundStyle(recipe.isBookmarked ? AppTheme.primary : AppTheme.textPrimary)
                        }
                        .accessibilityLabel(recipe.isBookmarked ? "Remove bookmark" : "Add bookmark")

                        Button {
                            showingEdit = true
                            PostHogSDK.shared.capture("ai_recipe_added", properties: [
                                    "meal_type": "dinner"
                            ])
                            print("🚀 PostHog successfully initialized via AppDelegate!")
                        } label: {
                            Image(systemName: "pencil")
                                .appFont(.callout)
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        
                        Button{
                            showCookMode = true
                        } label:{
                            Image(systemName: "frying.pan.fill")
                                .appFont(.callout)
                                .foregroundStyle(AppTheme.textPrimary)
                        }

                        Menu {
                            Button {
                                sharePDF()
                            } label: {
                                Label("Share PDF", systemImage: "doc.richtext")
                            }
                            Button {
                                shareRecipeText()
                            } label: {
                                Label("Share Recipe Text", systemImage: "text.alignleft")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .appFont(.callout)
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .accessibilityLabel("Share")
                    }
                }
            }
            .sheet(isPresented: $showingEdit) {
                RecipeEditView(recipe: recipe, onDismiss: { showingEdit = false })
            }
            .sheet(isPresented: $showingImport) {
                PasteLinkView(prefillURL: recipe.sourceURL) {
                    showingImport = false
                }
            }
            // Share-extension / auto-import flow stacks: dismiss PasteLink sheet → present this sheet → open Edit.
            // Presenting the edit sheet synchronously in `onAppear` often breaks hit testing (pencil / toolbar taps).
            .onAppear {
                guard openEditOnAppear else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    showingEdit = true
                }
            }
            .onAppear {
                scheduleStoreReviewAfterFirstGeneratedRecipeIfNeeded()
            }
            .fullScreenCover(isPresented: $showCookMode) {
                CookModeView(recipe: recipe)
            }
            .overlay {
                if isExportingPDF {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Preparing PDF…")
                        .padding(20)
                        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .sheet(isPresented: $showShareTextSheet) {
                ShareSheet(activityItems: [recipe.shareableExportText])
            }
            .sheet(isPresented: $showPDFPreview) {
                if let exportedPDFURL {
                    RecipePDFPreviewSheet(html: pdfPreviewHTML, pdfURL: exportedPDFURL)
                }
            }
            .errorPopup(message: $exportError)
            .task {
                await subManager.checkStatus()
            }
        }
    }

    /// YouTube always; Instagram/TikTok/Photos show backend-generated thumbnail (or placeholder).
    private var shouldShowVideoPreview: Bool {
        true
    }

    private func shareRecipeText() {
        Task { @MainActor in
            exportError = nil
            do {
                guard let userId = await SupabaseService.shared.currentUserIdString() else {
                    exportError = "Not signed in."
                    return
                }
                try await RecipeBackendService.shared.recordExportUsage(userId: userId)
                showShareTextSheet = true
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func sharePDF() {
        Task { @MainActor in
            exportError = nil
            isExportingPDF = true
            defer { isExportingPDF = false }
            do {
                guard let userId = await SupabaseService.shared.currentUserIdString() else {
                    exportError = "Not signed in."
                    return
                }
                try await RecipeBackendService.shared.recordExportUsage(userId: userId)
                let html = RecipePDFHTMLBuilder.buildHTML(from: recipe, servings: displayServings)
                let pdfData = try await RecipePDFExportService.generatePDF(html: html)
                exportedPDFURL = try recipe.temporaryPDFExportURL(data: pdfData)
                pdfPreviewHTML = html
                showPDFPreview = true
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    /// After the user’s first AI/import-backed recipe is in Home, prompt for an App Store review once when they open it.
    private func scheduleStoreReviewAfterFirstGeneratedRecipeIfNeeded() {
        guard !didRequestStoreReviewAfterFirstGeneratedRecipe else { return }

        let ownerId = recipe.ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ownerId.isEmpty, ownerId != Recipe.localOnboardingOwnerPlaceholder else { return }
        guard Self.isLikelyGeneratedRecipe(recipe) else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
        #endif

        let recipeId = recipe.id
        Task { @MainActor in
            var descriptor = FetchDescriptor<Recipe>(
                predicate: #Predicate<Recipe> { r in
                    r.ownerUserId == ownerId && r.deletedAt == nil
                }
            )
            descriptor.fetchLimit = 2
            let rows = (try? modelContext.fetch(descriptor)) ?? []
            guard rows.count == 1, rows.first?.id == recipeId else { return }

            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }

            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            guard let scene else { return }

            AppStore.requestReview(in: scene)
            didRequestStoreReviewAfterFirstGeneratedRecipe = true
        }
    }

    /// Heuristic: recipe came from link/photo import or backend analyze (not a blank manual-only entry).
    private static func isLikelyGeneratedRecipe(_ recipe: Recipe) -> Bool {
        let url = recipe.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = url.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return true }
        if lower.hasPrefix("photos://") { return true }
        if !recipe.downloadedVideoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }
    
    private var headerRow: some View {
        Text(recipe.title.isEmpty ? "Recipe" : recipe.title)
            .appFont(.titleBold)
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }
    
    private var videoSection: some View {
        VideoThumbnailView(
            sourceURL: recipe.sourceURL,
            downloadedVideoURL: recipe.downloadedVideoURL,
            source: recipe.sourceEnum,
            dishHeroTimestampSeconds: recipe.dishHeroTimestampSeconds
        )
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius)
                .stroke(AppTheme.textSecondary.opacity(0.3), lineWidth: AppTheme.boxBorderWidth)
        )
    }
    
    private var estimateTimeSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .foregroundStyle(AppTheme.primary)
            if recipe.prepMinutes > 0 {
                Text("Prep: \(recipe.prepMinutes) min • Cook: \(recipe.estimatedCookingMinutes) min")
                    .appFont(.callout)
            } else {
                Text("Cook: \(recipe.estimatedCookingMinutes) min")
                    .appFont(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }
    
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label("Ingredients", systemImage: "basket.fill")
                    .appFont(.headlineBold)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer(minLength: 8)
                ServingStepperControl(value: $displayServings)
            }

            let lines = recipe.ingredientLines
            if lines.isEmpty {
                Text("No ingredients listed")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                let scale = servingScaleFactor
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    ingredientRow(index: index, line: line, linesCount: lines.count, scale: scale)
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
        .onAppear { resetDisplayServings() }
        .onChange(of: recipe.id) { _, _ in resetDisplayServings() }
        .onChange(of: recipe.estimatedServings) { _, _ in resetDisplayServings() }
    }

    private var servingScaleFactor: Double {
        let base = max(1, recipe.estimatedServings)
        return Double(displayServings) / Double(base)
    }

    private func resetDisplayServings() {
        displayServings = max(1, recipe.estimatedServings)
    }
    
    private func ingredientRow(index: Int, line: String, linesCount: Int, scale: Double) -> some View {
        let parsed = IngredientLine.parse(line)
        let scaledAmount = IngredientAmountScaler.scaledAmount(parsed.amount, factor: scale)
        return IngredientCheckRow(
            name: parsed.name,
            amount: scaledAmount,
            checked: recipe.ingredientChecked(at: index)
        ) {
            recipe.toggleIngredientCheck(at: index, linesCount: linesCount)
            touchRecipeForSync()
        }
    }

    private func touchRecipeForSync() {
        recipe.updatedAt = Date()
        try? modelContext.save()
        Task { await SyncService.shared.push(modelContainer: modelContext.container) }
    }

    private func handleBookmarkTap() {
        if !recipe.isBookmarked {
            recipe.isBookmarked = true
            touchRecipeForSync()
        }
        onBookmarkNavigate?()
    }
    
    /// Steps: vertical circle-line timeline (1 — 2 — 3)
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack{
                Label("Steps", systemImage: "list.number")
                    .appFont(.headlineBold)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            }
            .padding(.vertical,0)
            
            let steps = recipe.stepLines
            if steps.isEmpty {
                Text("No steps listed")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                        stepRow(
                            number: index + 1,
                            text: text,
                            isLast: index == steps.count - 1
                        )
                        if index < steps.count - 1 {
                            stepTimelineGapConnector()
                        }
                    }
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
        .onTapGesture {
            showCookMode = true
        }
    }

    private static let stepTimelineSpacing: CGFloat = 16

    private func stepRow(number: Int, text: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("\(number)")
                    .appFont(.headlineBold)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black, in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)
            .frame(maxHeight: .infinity, alignment: .top)

            Text(text)
                .appFont(.callout)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    /// Vertical segment in the gap between steps (aligned with numbered circles).
    private func stepTimelineGapConnector() -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Color.black)
                .frame(width: 3, height: Self.stepTimelineSpacing)
                .frame(width: 32)
            Spacer(minLength: 0)
        }
    }
    
    private var NoteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notes", systemImage: "note.text")
                .appFont(.headlineBold)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(recipe.notes)
                .appFont(.notes)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 72)
                .padding(12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .boxStyle()
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Nutrition", systemImage: "chart.pie.fill")
                .appFont(.headlineBold)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            NutritionIndicatorView(
                calories: max(recipe.nutritionCalories, 0),
                proteinGrams: recipe.nutritionProteinGrams,
                carbsGrams: recipe.nutritionCarbsGrams,
                fatGrams: recipe.nutritionFatGrams,
                macros: recipe.nutritionMacroMetrics
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .boxStyle()
    }
    
    private var ratingSection: some View {
        HStack(spacing: 10) {
            Text("Rate this recipe")
                .appFont(.body)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= recipe.rating ? "star.fill" : "star")
                                .foregroundStyle(star <= recipe.rating ? AppTheme.primary : AppTheme.textSecondary.opacity(0.4))
                                .onTapGesture {
                                    if recipe.rating == star {
                                        recipe.rating = 0
                                        recipe.triedBefore = false
                                    } else {
                                        recipe.rating = star
                                        recipe.triedBefore = true
                                    }
                                    touchRecipeForSync()
                                }
                        }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }
    
    private var openLinkSection: some View {
        Link(destination: URL(string: recipe.sourceURL) ?? URL(string: "https://example.com")!) {
            HStack {
                Text("Open in \(recipe.sourceEnum.rawValue)")
                    .appFont(.headlineBold)
                    .foregroundStyle(.black)
                Image(systemName: "arrow.up.right")
                    .appFont(.caption)
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
        }
        .background(AppTheme.textSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius)
                .stroke(AppTheme.textSecondary.opacity(0.25), lineWidth: AppTheme.boxBorderWidth)
        )
    }
}

// MARK: - Share sheet (wraps UIActivityViewController; export quota via RecipeBackendService before present)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Recipe.self, configurations: config)
    let ctx = ModelContext(container)
    let recipe = Recipe(
        ownerUserId: "preview-user",
        title: "Sample Recipe",
        sourceURL: "https://www.youtube.com/watch?v=noaf6TrczKs&list=RDnoaf6TrczKs&start_radio=1",
        creator: "Chef",
        ingredients: "Salt\nPepper\nOlive oil",
        stepsContent: "Step 1: Mix Mix Mix Mix Mix Mix Mix Mix Mix Mix Mix MixMix Mix Mix Mix Mix MixMix Mix Mix Mix Mix Mix Mix Mix Mix Mix Mix MixMix Mix Mix Mix Mix Mix Mix Mix Mix Mix Mix Mix  \nStep 2: Bake"
    )
    ctx.insert(recipe)
    try! ctx.save()
    return RecipePageView(recipe: recipe, onDismiss: {})
        .modelContainer(container)
}
