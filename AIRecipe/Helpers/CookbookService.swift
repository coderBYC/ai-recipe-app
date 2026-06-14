import Foundation
import SwiftData

enum CookbookService {
    static let defaultCookbookName = "My Recipes"
    private static let legacyCookbookMigrationDefaultsKey = "cookbookLegacyMigration_v1"

    private static func activeCookbookDefaultsKey(ownerUserId: String) -> String {
        "activeCookbookId.\(ownerUserId)"
    }

    static func activeCookbookId(for ownerUserId: String) -> String? {
        let raw = UserDefaults.standard.string(forKey: activeCookbookDefaultsKey(ownerUserId: ownerUserId))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    static func setActiveCookbookId(_ cookbookId: String, ownerUserId: String) {
        UserDefaults.standard.set(cookbookId, forKey: activeCookbookDefaultsKey(ownerUserId: ownerUserId))
    }

    /// Ensures a default cookbook exists and assigns legacy on-device recipes without a cookbook.
    @MainActor
    @discardableResult
    static func ensureLibrary(for ownerUserId: String, modelContext: ModelContext) -> Cookbook {
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else {
            return fetchOrCreateDefaultCookbook(ownerUserId: ownerUserId, modelContext: modelContext)
        }

        Recipe.migrateUnassignedOwnersOnce(modelContext: modelContext, assignedTo: owner)
        runLegacyCookbookMigrationIfNeeded(signedInUserId: owner, modelContext: modelContext)

        let defaultBook = fetchOrCreateDefaultCookbook(ownerUserId: owner, modelContext: modelContext)
        migrateRecipesWithoutCookbook(ownerUserId: owner, defaultCookbookId: defaultBook.id, modelContext: modelContext)
        _ = LegacyRecipeStoreRecovery.reassignHiddenLocalRecipes(
            modelContext: modelContext,
            ownerUserId: owner
        )

        if activeCookbookId(for: owner) == nil {
            setActiveCookbookId(defaultBook.id, ownerUserId: owner)
        }
        return defaultBook
    }

    /// One-time pass after the cookbook feature ships: move every stored recipe for this user into **My Recipes**.
    @MainActor
    static func runLegacyCookbookMigrationIfNeeded(signedInUserId: String, modelContext: ModelContext) {
        let owner = signedInUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return }

        let migrationKey = "\(legacyCookbookMigrationDefaultsKey).\(owner)"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let defaultBook = fetchOrCreateDefaultCookbook(ownerUserId: owner, modelContext: modelContext)
        migrateRecipesWithoutCookbook(ownerUserId: owner, defaultCookbookId: defaultBook.id, modelContext: modelContext)
        migrateOrphanedRecipesToUser(ownerUserId: owner, defaultCookbookId: defaultBook.id, modelContext: modelContext)

        if activeCookbookId(for: owner) == nil {
            setActiveCookbookId(defaultBook.id, ownerUserId: owner)
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    @MainActor
    static func createCookbook(
        name: String,
        ownerUserId: String,
        modelContext: ModelContext
    ) -> Cookbook? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return nil }

        let existing = fetchCookbooks(ownerUserId: owner, modelContext: modelContext)
        let book = Cookbook(
            ownerUserId: owner,
            name: trimmed,
            isDefault: false,
            sortOrder: existing.count
        )
        modelContext.insert(book)
        try? modelContext.save()
        setActiveCookbookId(book.id, ownerUserId: owner)
        return book
    }

    @MainActor
    static func cookbookIdForNewRecipe(ownerUserId: String, modelContext: ModelContext) -> String {
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let active = activeCookbookId(for: owner) {
            return active
        }
        return ensureLibrary(for: owner, modelContext: modelContext).id
    }

    @MainActor
    private static func fetchOrCreateDefaultCookbook(
        ownerUserId: String,
        modelContext: ModelContext
    ) -> Cookbook {
        let desc = FetchDescriptor<Cookbook>(
            predicate: #Predicate<Cookbook> { $0.ownerUserId == ownerUserId && $0.isDefault == true }
        )
        if let existing = try? modelContext.fetch(desc), let book = existing.first {
            return book
        }

        let book = Cookbook(
            ownerUserId: ownerUserId,
            name: defaultCookbookName,
            isDefault: true,
            sortOrder: 0
        )
        modelContext.insert(book)
        try? modelContext.save()
        return book
    }

    @MainActor
    private static func migrateRecipesWithoutCookbook(
        ownerUserId: String,
        defaultCookbookId: String,
        modelContext: ModelContext
    ) {
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return }

        let desc = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> {
                $0.ownerUserId == owner && $0.deletedAt == nil && $0.cookbookId == ""
            }
        )
        guard let rows = try? modelContext.fetch(desc), !rows.isEmpty else { return }

        for recipe in rows {
            recipe.cookbookId = defaultCookbookId
            recipe.updatedAt = Date()
        }
        try? modelContext.save()
    }

    /// Assigns legacy rows that still have no owner to the signed-in user, then places them in the default cookbook.
    @MainActor
    private static func migrateOrphanedRecipesToUser(
        ownerUserId: String,
        defaultCookbookId: String,
        modelContext: ModelContext
    ) {
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else { return }

        let desc = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> {
                $0.deletedAt == nil && $0.cookbookId == "" && $0.ownerUserId == ""
            }
        )
        guard let rows = try? modelContext.fetch(desc), !rows.isEmpty else { return }

        for recipe in rows {
            recipe.ownerUserId = owner
            recipe.cookbookId = defaultCookbookId
            recipe.updatedAt = Date()
        }
        try? modelContext.save()
    }

    @MainActor
    static func fetchCookbooks(ownerUserId: String, modelContext: ModelContext) -> [Cookbook] {
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = FetchDescriptor<Cookbook>(
            predicate: #Predicate<Cookbook> { $0.ownerUserId == owner },
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt),
            ]
        )
        return (try? modelContext.fetch(desc)) ?? []
    }

    @MainActor
    @discardableResult
    static func renameCookbook(_ cookbook: Cookbook, name: String, modelContext: ModelContext) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        cookbook.name = trimmed
        try? modelContext.save()
        return true
    }

    /// Moves recipes to the default cookbook, then deletes the cookbook. Default cookbook cannot be deleted.
    @MainActor
    @discardableResult
    static func deleteCookbook(
        _ cookbook: Cookbook,
        ownerUserId: String,
        modelContext: ModelContext
    ) -> Bool {
        guard !cookbook.isDefault else { return false }
        let owner = ownerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, cookbook.ownerUserId == owner else { return false }

        let defaultBook = fetchOrCreateDefaultCookbook(ownerUserId: owner, modelContext: modelContext)
        let cookbookId = cookbook.id

        let recipeDesc = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> {
                $0.ownerUserId == owner && $0.cookbookId == cookbookId && $0.deletedAt == nil
            }
        )
        if let recipes = try? modelContext.fetch(recipeDesc) {
            for recipe in recipes {
                recipe.cookbookId = defaultBook.id
                recipe.updatedAt = Date()
            }
        }

        if activeCookbookId(for: owner) == cookbookId {
            setActiveCookbookId(defaultBook.id, ownerUserId: owner)
        }

        modelContext.delete(cookbook)
        try? modelContext.save()
        return true
    }
}
