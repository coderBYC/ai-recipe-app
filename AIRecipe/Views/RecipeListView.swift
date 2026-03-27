import SwiftUI
import SwiftData

// MARK: - Home Page

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var addSheet: AddRecipeSheet?
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var selectedRecipe: Recipe?
    @State private var openEditWhenRecipeOpens = false
    @State private var isProcessingPhoto = false
    @State private var pendingPhotoData: Data?
    @State private var searchText = ""
    @State private var selectedTag: String?
    
    private let recipeTags = ["All", "YouTube", "Instagram", "TikTok", "Done", "Recent", "Rating ↓", "Rating ↑"]
    
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
            } else if tag == "YouTube" || tag == "Instagram" || tag == "TikTok" {
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
                    searchBar
                    tagsSection
                    recipeListContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                
                if isProcessingPhoto {
                    processingPhotoOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Home")
                        .appFont(.largeTitle)
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
            .onChange(of: isProcessingPhoto) { _, processing in
                if processing, let data = pendingPhotoData {
                    processPhotoAndOpenDetail(imageData: data)
                }
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
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }
    
    private var tagsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recipeTags, id: \.self) { tag in
                    Button {
                        selectedTag = selectedTag == tag ? nil : tag
                    } label: {
                        Group {
                            switch tag {
                            case "YouTube":
                                SourceIconView(source: .youtube)
                            case "Instagram":
                                SourceIconView(source: .instagram)
                            case "TikTok":
                                SourceIconView(source: .tiktok)
                            default:
                                Text(tag)
                                    .appFont(.callout)
                            }
                        }
                        .foregroundStyle(selectedTag == tag ? .white : AppTheme.textPrimary)
                        .frame(minWidth: 32, minHeight: 28)
                        .padding(.horizontal, tag == "All" || tag == "Done" || tag == "Recent" ? 12 : 10)
                        .padding(.vertical, 5)
                    }
                    .background(selectedTag == tag ? Color.black : AppTheme.cardBackground)
                    .boxStyle(cornerRadius: 5)
                    .padding(.horizontal,3)
                }
            }
            
        }
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
            .padding(.vertical,10)
            .buttonStyle(PlainButtonStyle()).boxStyle()
            
                
            .tint(AppTheme.primary)
            .appFont(.callout)
            .padding(.top,8)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
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
                .padding(.bottom, 24)
            }
        }
    }
    
    @ViewBuilder
    private func addSheetContent(_ sheet: AddRecipeSheet) -> some View {
        switch sheet {
        case .addLink:
            PasteLinkView(prefillURL: nil) { recipe in
                addSheet = nil
                selectedRecipe = recipe
                openEditWhenRecipeOpens = true
            }
        case .addLinkWithURL(let url):
            PasteLinkView(prefillURL: url) { recipe in
                addSheet = nil
                selectedRecipe = recipe
                openEditWhenRecipeOpens = true
            }
        case .scanQR:
            QRCodeScannerView { scannedURL in
                addSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    addSheet = .addLinkWithURL(scannedURL)
                }
            }
        case .takePhoto:
            ImagePickerView(sourceType: .camera) { imageData in
                addSheet = nil
                pendingPhotoData = imageData
                isProcessingPhoto = true
            }
        case .manualRecipe:
            AddRecipeView()
        }
    }
    
    private var processingPhotoOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.2).tint(.white)
                Text("Processing photo…").appFont(.headline).foregroundStyle(.white)
            }
        }
    }
    
    private func processPhotoAndOpenDetail(imageData: Data) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let recipe = Recipe(
                title: "Imported recipe",
                source: .youtube,
                sourceURL: "",
                creator: "",
                timestamp: "",
                ingredients: "",
                estimatedCookingMinutes: 0,
                totalSteps: 0,
                triedBefore: false,
                notes: "",
                customImageData: imageData
            )
            modelContext.insert(recipe)
            pendingPhotoData = nil
            isProcessingPhoto = false
            selectedRecipe = recipe
        }
    }
}

// MARK: - Recipe row (box style)

struct RecipeRowView: View {
    let recipe: Recipe
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                    if recipe.triedBefore || recipe.rating > 0 {
                        Text("Done")
                            .appFont(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.triedBadge, in: Capsule())
                    }
                }
                if recipe.rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= recipe.rating ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundStyle(star <= recipe.rating ? AppTheme.primary : AppTheme.textSecondary.opacity(0.4))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }
}

#Preview("Recipe list") {
    RecipeListView(addSheet: .constant(nil))
        .modelContainer(for: Recipe.self, inMemory: true)
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
    case scanQR
    case takePhoto
    case manualRecipe
    var id: String {
        switch self {
        case .addLink: return "addLink"
        case .addLinkWithURL(let u): return "addLink-\(u)"
        case .scanQR: return "scanQR"
        case .takePhoto: return "takePhoto"
        case .manualRecipe: return "manualRecipe"
        }
    }
}
