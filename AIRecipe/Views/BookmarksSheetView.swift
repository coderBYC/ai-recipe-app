import SwiftData
import SwiftUI

struct BookmarksSheetView: View {
    let filterOwnerId: String
    var onSelectRecipe: (Recipe) -> Void
    var onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]

    init(
        filterOwnerId: String,
        onSelectRecipe: @escaping (Recipe) -> Void,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.filterOwnerId = filterOwnerId
        self.onSelectRecipe = onSelectRecipe
        self.onDismiss = onDismiss
        let oid = filterOwnerId
        _recipes = Query(
            filter: #Predicate<Recipe> { r in
                r.deletedAt == nil && r.ownerUserId == oid && r.isBookmarked
            },
            sort: \Recipe.updatedAt,
            order: .reverse
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(recipes) { recipe in
                                RecipeRowView(recipe: recipe)
                                    .onTapGesture {
                                        onSelectRecipe(recipe)
                                    }
                                    .contextMenu {
                                        Button {
                                            removeBookmark(recipe)
                                        } label: {
                                            Label("Remove bookmark", systemImage: "bookmark.slash")
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                }
            }
            .background(AppTheme.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                        .appFont(.callout)
                }
                ToolbarItem(placement: .principal) {
                    Text("Bookmarks")
                        .nanumAppFont(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bookmark")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.primary.opacity(0.85))
            Text("No bookmarks yet")
                .appFont(.title3)
                .foregroundStyle(AppTheme.textPrimary)
            Text("Tap the bookmark on a recipe to save it here.")
                .appFont(.callout)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func removeBookmark(_ recipe: Recipe) {
        recipe.isBookmarked = false
        recipe.updatedAt = Date()
        try? modelContext.save()
        Task { await SyncService.shared.push(modelContainer: modelContext.container) }
    }
}
