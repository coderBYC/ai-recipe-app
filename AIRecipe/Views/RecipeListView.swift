import SwiftUI
import SwiftData

// MARK: - Home Page

struct RecipeListView: View {
    /// Supabase Auth `user.id.uuidString`; only this user’s recipes appear in Home.
    let filterOwnerId: String
    @Environment(\.modelContext) private var modelContext
    @Binding var activeCookbookId: String?
    @Binding var addSheet: AddRecipeSheet?
    @Binding var showImports: Bool
    @Binding var showSettings: Bool
    @Query private var recipes: [Recipe]
    @Query private var cookbooks: [Cookbook]

    init(
        filterOwnerId: String,
        activeCookbookId: Binding<String?>,
        addSheet: Binding<AddRecipeSheet?>,
        showImports: Binding<Bool> = .constant(false),
        showSettings: Binding<Bool> = .constant(false)
    ) {
        self.filterOwnerId = filterOwnerId
        _activeCookbookId = activeCookbookId
        _addSheet = addSheet
        _showImports = showImports
        _showSettings = showSettings
        let oid = filterOwnerId
        _recipes = Query(
            filter: #Predicate<Recipe> { r in
                r.deletedAt == nil && r.ownerUserId == oid
            },
            sort: \Recipe.createdAt,
            order: .reverse
        )
        _cookbooks = Query(
            filter: #Predicate<Cookbook> { $0.ownerUserId == oid },
            sort: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt),
            ]
        )
    }
    @State private var selectedRecipe: Recipe?
    @State private var openEditWhenRecipeOpens = false
    @State private var searchText = ""
    @State private var showBookmarksSheet = false
    @State private var showAIAssistantComingSoon = false
    @State private var editingCookbook: Cookbook?
    @State private var cookbookPendingDelete: Cookbook?
    @State private var cookbookRecipesSheet: Cookbook?

    private let cookbookColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    /// Screen padding for text fields and cards; scroll views extend full width then re-inset so shadows aren’t clipped.
    private let contentInset: CGFloat = 16

    /// If the selected cookbook is empty but other recipes exist, fall back to My Recipes.
    private func reconcileActiveCookbook(defaultBookId: String) {
        guard let cookbookId = activeCookbookId, !cookbookId.isEmpty else { return }
        let inActive = recipes.filter { $0.cookbookId == cookbookId }
        if inActive.isEmpty, !recipes.isEmpty {
            activeCookbookId = defaultBookId
            CookbookService.setActiveCookbookId(defaultBookId, ownerUserId: filterOwnerId)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.surface
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    searchBar
                    cookbooksSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, contentInset)
                .padding(.top, 10)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Home")
                        .nanumAppFont(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 18) {
                        Button {
                            showAIAssistantComingSoon = true
                        } label: {
                            Image("OnboardingHolUpMeme")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityLabel("AI assistant")

                        Button {
                            showBookmarksSheet = true
                        } label: {
                            Image(systemName: "bookmark")
                                .font(AppTheme.bitterFont(size: 18, weight: .regular))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .accessibilityLabel("Bookmarks")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 18) {
                        Button {
                            showImports = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(AppTheme.bitterFont(size: 18, weight: .regular))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .accessibilityLabel("Imports")

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(AppTheme.bitterFont(size: 18, weight: .regular))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .onAppear {
                Recipe.migrateEstimatedServingsOnce(modelContext: modelContext)
                if !filterOwnerId.isEmpty {
                    _ = LegacyRecipeStoreRecovery.recoverIfNeeded(
                        modelContext: modelContext,
                        ownerUserId: filterOwnerId
                    )
                }
                let defaultBook = CookbookService.ensureLibrary(for: filterOwnerId, modelContext: modelContext)
                if activeCookbookId == nil {
                    activeCookbookId = CookbookService.activeCookbookId(for: filterOwnerId) ?? defaultBook.id
                }
                reconcileActiveCookbook(defaultBookId: defaultBook.id)
                Task { await SyncService.shared.silentSync(modelContainer: modelContext.container) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openBookmarksSheet)) { _ in
                showBookmarksSheet = true
            }
            .alert("Coming soon", isPresented: $showAIAssistantComingSoon) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your AI kitchen assistant marmot is on the way.")
            }
            .sheet(isPresented: $showBookmarksSheet) {
                BookmarksSheetView(
                    filterOwnerId: filterOwnerId,
                    onSelectRecipe: { recipe in
                        showBookmarksSheet = false
                        selectedRecipe = recipe
                    },
                    onDismiss: { showBookmarksSheet = false }
                )
            }
            .sheet(item: $editingCookbook) { book in
                EditCookbookSheet(cookbook: book)
            }
            .alert("Delete cookbook?", isPresented: Binding(
                get: { cookbookPendingDelete != nil },
                set: { if !$0 { cookbookPendingDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { cookbookPendingDelete = nil }
                Button("Delete", role: .destructive) {
                    deletePendingCookbook()
                }
            } message: {
                if let book = cookbookPendingDelete {
                    let title = book.name.isEmpty ? CookbookService.defaultCookbookName : book.name
                    Text("Recipes in “\(title)” will move to My Recipes.")
                }
            }
            .sheet(item: $addSheet) { sheet in
                addSheetContent(sheet)
            }
            .sheet(item: $cookbookRecipesSheet) { book in
                CookbookRecipesSheetView(
                    cookbook: book,
                    filterOwnerId: filterOwnerId,
                    searchText: searchText,
                    onSelectRecipe: { recipe in
                        cookbookRecipesSheet = nil
                        selectedRecipe = recipe
                    }
                )
            }
            .sheet(item: $selectedRecipe) { recipe in
                RecipePageView(
                    recipe: recipe,
                    onDismiss: { selectedRecipe = nil; openEditWhenRecipeOpens = false },
                    openEditOnAppear: openEditWhenRecipeOpens,
                    onBookmarkNavigate: {
                        selectedRecipe = nil
                        openEditWhenRecipeOpens = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showBookmarksSheet = true
                        }
                    }
                )
            }
        }
    }
    
    private var cookbooksSection: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: cookbookColumns, spacing: 16) {
                ForEach(cookbooks) { book in
                    CookbookCoverView(
                        name: book.name.isEmpty ? CookbookService.defaultCookbookName : book.name,
                        isSelected: activeCookbookId == book.id
                    )
                    .onTapGesture {
                        activeCookbookId = book.id
                        CookbookService.setActiveCookbookId(book.id, ownerUserId: filterOwnerId)
                        cookbookRecipesSheet = book
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .contextMenu {
                        Button {
                            editingCookbook = book
                        } label: {
                            Label("Edit name", systemImage: "pencil")
                        }
                        if !book.isDefault {
                            Button(role: .destructive) {
                                cookbookPendingDelete = book
                            } label: {
                                Label("Delete cookbook", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func deletePendingCookbook() {
        guard let book = cookbookPendingDelete else { return }
        let deletedId = book.id
        if CookbookService.deleteCookbook(book, ownerUserId: filterOwnerId, modelContext: modelContext) {
            if cookbookRecipesSheet?.id == deletedId {
                cookbookRecipesSheet = nil
            }
            if activeCookbookId == deletedId {
                let defaultBook = CookbookService.ensureLibrary(for: filterOwnerId, modelContext: modelContext)
                activeCookbookId = defaultBook.id
            }
        }
        cookbookPendingDelete = nil
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.textSecondary)
            TextField("Search recipes", text: $searchText)
                .textFieldStyle(.plain)
                .appFont(.body)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
        )
    }
    
    @ViewBuilder
    private func addSheetContent(_ sheet: AddRecipeSheet) -> some View {
        switch sheet {
        case .addLink:
            PasteLinkView(prefillURL: nil) {
                addSheet = nil
            }
        case .addLinkWithURL(let url):
            PasteLinkView(prefillURL: url) {
                addSheet = nil
            }
        case .addLinkWithURLAutoProcess(let url):
            PasteLinkView(prefillURL: url, autoProcessOnAppear: true) {
                addSheet = nil
            }
        case .manualRecipe:
            AddRecipeView()
        case .photoLibraryVideo:
            PhotoLibraryVideoImportView {
                addSheet = nil
            }
        }
    }
}

// MARK: - Cookbook cover (asset image + top title)

struct CookbookCoverView: View {
    let name: String
    let isSelected: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width * 1.12

            ZStack(alignment: .top) {
                Image("cookbook")
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)

                Text(name)
                    .nanumAppFont(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, width * 0.14)
                    .padding(.top, width * 0.4)
                    .frame(width: width, alignment: .top)
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(0.89, contentMode: .fit)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Cookbook recipes sheet

struct CookbookRecipesSheetView: View {
    let cookbook: Cookbook
    let filterOwnerId: String
    let searchText: String
    var onSelectRecipe: (Recipe) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var recipes: [Recipe]

    private let contentInset: CGFloat = 16
    private var shadowPad: CGFloat { AppTheme.boxShadowOffset }

    init(
        cookbook: Cookbook,
        filterOwnerId: String,
        searchText: String,
        onSelectRecipe: @escaping (Recipe) -> Void
    ) {
        self.cookbook = cookbook
        self.filterOwnerId = filterOwnerId
        self.searchText = searchText
        self.onSelectRecipe = onSelectRecipe
        let oid = filterOwnerId
        let cid = cookbook.id
        _recipes = Query(
            filter: #Predicate<Recipe> { r in
                r.deletedAt == nil && r.ownerUserId == oid && r.cookbookId == cid
            },
            sort: \Recipe.createdAt,
            order: .reverse
        )
    }

    private var displayName: String {
        cookbook.name.isEmpty ? CookbookService.defaultCookbookName : cookbook.name
    }

    private var filteredRecipes: [Recipe] {
        guard !searchText.isEmpty else { return recipes }
        return recipes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.creator.localizedCaseInsensitiveContains(searchText) ||
            $0.ingredients.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.surface.ignoresSafeArea()

                Group {
                    if filteredRecipes.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No recipes" : "No matches",
                            systemImage: "book.closed",
                            description: Text(
                                searchText.isEmpty
                                    ? "Add a recipe to this cookbook."
                                    : "Try a different search."
                            )
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredRecipes) { recipe in
                                    RecipeRowView(recipe: recipe)
                                        .onTapGesture { onSelectRecipe(recipe) }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                recipe.deletedAt = Date()
                                                recipe.updatedAt = Date()
                                                try? modelContext.save()
                                                Task { await SyncService.shared.push(modelContainer: modelContext.container) }
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.top, AppTheme.boxBorderWidth)
                            .padding(.leading, contentInset)
                            .padding(.trailing, contentInset + shadowPad)
                            .padding(.bottom, 24 + shadowPad)
                        }
                    }
                }
                .padding(.horizontal, contentInset)
                .padding(.top, 8)
            }
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(650)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Recipe row (box style)

struct RecipeRatingStarsView: View {
    let rating: Int
    var starSize: AppTheme.FontStyle = .caption2

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .appFont(starSize)
                    .foregroundStyle(star <= rating ? AppTheme.primary : AppTheme.textSecondary.opacity(0.35))
            }
        }
        .accessibilityLabel(rating > 0 ? "\(rating) out of 5 stars" : "Not rated")
    }
}

struct RecipeRowView: View {
    let recipe: Recipe

    private var creatorLine: String {
        let name = recipe.creator.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unknown creator" : name
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title.isEmpty ? "Untitled recipe" : recipe.title)
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    SourceIconView(source: recipe.sourceEnum)
                        .frame(width: 18, height: 18)
                    Text(creatorLine)
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    RecipeRatingStarsView(rating: recipe.rating)
                    if recipe.estimatedCookingMinutes > 0 {
                        Text("\(recipe.estimatedCookingMinutes) min")
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RecipeListThumbnailView(recipe: recipe)

            Image(systemName: "chevron.right")
                .appFont(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(14)
        .boxStyle(cornerRadius: 8)
    }
}

#Preview("Recipe list") {
    RecipeListView(filterOwnerId: "preview-user", activeCookbookId: .constant(nil), addSheet: .constant(nil))
        .modelContainer(for: [Recipe.self, Cookbook.self], inMemory: false)
}

#Preview("Recipe row") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Recipe.self, configurations: config)
    let ctx = ModelContext(container)
    let recipe = Recipe(
        ownerUserId: "preview-user",
        title: "Viral Feta Pasta",
        source: .instagram,
        creator: "Chef",
        estimatedCookingMinutes: 25,
        rating: 4
    )
    ctx.insert(recipe)
    try! ctx.save()
    return RecipeRowView(recipe: recipe)
        .modelContainer(container)
}

enum AddRecipeSheet: Identifiable {
    case addLink
    case addLinkWithURL(String)
    case addLinkWithURLAutoProcess(String)
    case manualRecipe
    case photoLibraryVideo
    var id: String {
        switch self {
        case .addLink: return "addLink"
        case .addLinkWithURL(let u): return "addLink-\(u)"
        case .addLinkWithURLAutoProcess(let u): return "addLink-auto-\(u)"
        case .manualRecipe: return "manualRecipe"
        case .photoLibraryVideo: return "photoLibraryVideo"
        }
    }
}
