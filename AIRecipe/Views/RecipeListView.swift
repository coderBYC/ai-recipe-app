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
    @State private var selectedTag: String?

    /// Screen padding for text fields and cards; scroll views extend full width then re-inset so shadows aren’t clipped.
    private let contentInset: CGFloat = 16
    private var shadowPad: CGFloat { AppTheme.boxShadowOffset }

    private let recipeTags = ["All", "YouTube", "Instagram", "TikTok", "Photos", "Done", "Recent", "Rating ↓", "Rating ↑"]
    
    var filteredRecipes: [Recipe] {
        var list = recipes
        if let cookbookId = activeCookbookId, !cookbookId.isEmpty {
            list = list.filter { $0.cookbookId == cookbookId }
        }
        if !searchText.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.creator.localizedCaseInsensitiveContains(searchText) ||
                $0.ingredients.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let tag = selectedTag, tag != "All" {
            if tag == "Done" {
                list = list.filter { $0.triedBefore || $0.rating > 0 }
            } else if tag == "Recent" {
                list = Array(list.prefix(10))
            } else if tag == "YouTube" || tag == "Instagram" || tag == "TikTok" || tag == "Photos" {
                list = list.filter { $0.source == tag }
            } else if tag == "Rating ↓" {
                list = list.sorted {
                    if $0.rating == $1.rating {
                        return $0.createdAt > $1.createdAt
                    }
                    return $0.rating > $1.rating
                }
            } else if tag == "Rating ↑" {
                list = list.sorted {
                    if $0.rating == $1.rating {
                        return $0.createdAt > $1.createdAt
                    }
                    return $0.rating < $1.rating
                }
            }
        }
        return list
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.surface
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Group {
                        cookbooksSection
                            .fixedSize(horizontal: false, vertical: true)
                        searchBar
                        tagsSection
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .layoutPriority(1)

                    recipeListContent
                        .layoutPriority(0)
                        .frame(minHeight: 0, maxHeight: .infinity)
                }
                .padding(.leading, contentInset)
                .padding(.trailing, contentInset + shadowPad)
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
                let defaultBook = CookbookService.ensureLibrary(for: filterOwnerId, modelContext: modelContext)
                if activeCookbookId == nil {
                    activeCookbookId = CookbookService.activeCookbookId(for: filterOwnerId) ?? defaultBook.id
                }
                Task { await SyncService.shared.silentSync(modelContainer: modelContext.container) }
            }
            .sheet(item: $addSheet) { sheet in
                addSheetContent(sheet)
            }
            .sheet(item: $selectedRecipe) { recipe in
                RecipePageView(
                    recipe: recipe,
                    onDismiss: { selectedRecipe = nil; openEditWhenRecipeOpens = false },
                    openEditOnAppear: openEditWhenRecipeOpens
                )
            }
        }
    }
    
    private var cookbooksSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cookbooks) { book in
                    Button {
                        activeCookbookId = book.id
                        CookbookService.setActiveCookbookId(book.id, ownerUserId: filterOwnerId)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(book.name.isEmpty ? CookbookService.defaultCookbookName : book.name)
                            .appFont(.callout)
                            .fontWeight(activeCookbookId == book.id ? .semibold : .regular)
                            .foregroundStyle(activeCookbookId == book.id ? .white : AppTheme.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(activeCookbookId == book.id ? AppTheme.primary : AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
                    )
                }
            }
            .padding(.leading, contentInset)
            .padding(.trailing, contentInset)
        }
        .padding(.horizontal, -contentInset)
        .scrollClipDisabled()
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
    
    private var tagsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recipeTags, id: \.self) { tag in
                    Button {
                        selectedTag = selectedTag == tag ? nil : tag
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Group {
                            switch tag {
                            case "YouTube":
                                SourceIconView(source: .youtube)
                            case "Instagram":
                                SourceIconView(source: .instagram)
                            case "TikTok":
                                SourceIconView(source: .tiktok)
                            case "Photos":
                                SourceIconView(source: .photos)
                            default:
                                Text(tag)
                                    .appFont(.callout)
                            }
                        }
                        .foregroundStyle(selectedTag == tag ? .white : AppTheme.textPrimary)
                        .frame(minWidth: 32, minHeight: 28)
                        .padding(.horizontal, tag == "All" || tag == "Done" || tag == "Recent" ? 12 : 10)
                        .padding(.vertical, 3)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(selectedTag == tag ? AppTheme.primary : AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
                    )
                }
            }
            .padding(.leading, contentInset)
            .padding(.trailing, contentInset)
        }
        // Default clip: scrollClipDisabled on horizontal scroll can paint past the bar and
        // overlap/shear the recipe list; tag chips only need a stroke, not overflow.
        .padding(.horizontal, -contentInset)
        .scrollClipDisabled()
    }
    
    @ViewBuilder
    private var recipeListContent: some View {
        if filteredRecipes.isEmpty {
            Spacer()
            Text(cookbooks.isEmpty ? "No recipes" : "No recipes in this cookbook")
                .appFont(.body)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(filteredRecipes) { recipe in
                        RecipeRowView(recipe: recipe)
                            .onTapGesture { selectedRecipe = recipe }
                            .contextMenu {
                                Button(role: .destructive) {
                                    recipe.deletedAt = Date()
                                    recipe.updatedAt = Date()
                                    try? modelContext.save()
                                    Task { await SyncService.shared.push(modelContainer: modelContext.container) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
                // Inset so the first row’s 2px stroke isn’t sheared by ScrollView’s top clip.
                .padding(.top, AppTheme.boxBorderWidth)
                .padding(.leading, contentInset)
                .padding(.trailing, contentInset + shadowPad)
                .padding(.bottom, 24 + shadowPad)
            }
            .padding(.horizontal, -contentInset)
        }
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

// MARK: - Recipe row (box style)

struct RecipeRowView: View {
    let recipe: Recipe
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title.isEmpty ? "Untitled recipe" : recipe.title)
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                if !recipe.creator.isEmpty {
                    Text(recipe.creator)
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                HStack(spacing: 8) {
                    if !recipe.timestamp.isEmpty {
                        Label(recipe.timestamp, systemImage: "clock")
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    if recipe.estimatedCookingMinutes > 0 {
                        Text("\(recipe.estimatedCookingMinutes) min")
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                if recipe.rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= recipe.rating ? "star.fill" : "star")
                                .appFont(.caption2)
                                .foregroundStyle(star <= recipe.rating ? AppTheme.primary : AppTheme.textSecondary.opacity(0.4))
                        }
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
        creator: "Chef",
        timestamp: "2:30",
        estimatedCookingMinutes: 25,
        triedBefore: true
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
