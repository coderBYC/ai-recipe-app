import SwiftUI
import SwiftData

// MARK: - Home Page

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var addSheet: AddRecipeSheet?
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
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
                        .appFont(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
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
            Text("No recipes")
                .appFont(.body)
                .foregroundStyle(AppTheme.textSecondary)
            Button("Add recipe") {
                addSheet = .addLink
            }
            .padding(.horizontal,14)
            .padding(.vertical,5)
            .buttonStyle(PlainButtonStyle()).boxStyle(cornerRadius: 8)
            .tint(AppTheme.primary)
            .appFont(.callout)
            .padding(.top,8)
            Spacer()
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(filteredRecipes) { recipe in
                        RecipeRowView(recipe: recipe)
                            .onTapGesture { selectedRecipe = recipe }
                            .contextMenu {
                                Button(role: .destructive) {
                                    modelContext.delete(recipe)
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
    RecipeListView(addSheet: .constant(nil))
        .modelContainer(for: Recipe.self, inMemory: false)
}

#Preview("Recipe row") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Recipe.self, configurations: config)
    let ctx = ModelContext(container)
    let recipe = Recipe(title: "Viral Feta Pasta", creator: "Chef", timestamp: "2:30", estimatedCookingMinutes: 25, triedBefore: true)
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
