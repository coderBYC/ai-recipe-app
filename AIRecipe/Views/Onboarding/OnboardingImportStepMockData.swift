import SwiftUI
import SwiftData

enum OnboardingImportStepMockData {
    static let thumbnailPath = "/Users/bryanumich/Desktop/Desktop/AIRecipeApp/RecipeBackend/served_thumbnails/096f2a30-01be-44ed-b217-5998c635bd89.jpg"

    static func makeImportListContainer() -> (ModelContainer, [Recipe])? {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: Recipe.self, configurations: config)
            let ctx = ModelContext(container)

            let base = makeRecipe()

            let extra1 = Recipe(
                ownerUserId: Recipe.localOnboardingOwnerPlaceholder,
                title: "Garlic Butter Steak Bites",
                source: .tiktok,
                sourceURL: "https://tiktok.com/@demo/video/1",
                creator: "@quickkitchen",
                ingredients: "steak\nbutter\ngarlic\nsalt\npepper",
                estimatedCookingMinutes: 12,
                prepMinutes: 5,
                totalSteps: 3,
                stepsContent: "Cut steak.\nSear.\nToss with butter + garlic.",
                downloadedVideoURL: thumbnailPath,
                dishHeroTimestampSeconds: 1
            )

            let extra2 = Recipe(
                ownerUserId: Recipe.localOnboardingOwnerPlaceholder,
                title: "Crispy Chicken Wrap",
                source: .instagram,
                sourceURL: "https://instagram.com/reel/demo2",
                creator: "@wrapking",
                ingredients: "tortilla\nchicken\nlettuce\nsauce",
                estimatedCookingMinutes: 10,
                prepMinutes: 4,
                totalSteps: 3,
                stepsContent: "Cook chicken.\nAssemble.\nToast wrap.",
                downloadedVideoURL: thumbnailPath,
                dishHeroTimestampSeconds: 1
            )

            [base, extra1, extra2].forEach { ctx.insert($0) }
            try ctx.save()
            return (container, [base, extra1, extra2])
        } catch {
            return nil
        }
    }

    static func makeRecipe() -> Recipe {
        Recipe(
            ownerUserId: Recipe.localOnboardingOwnerPlaceholder,
            title: "Crispy Honey Garlic Salmon",
            source: .instagram,
            sourceURL: "https://instagram.com/reel/C8demoRecipe",
            creator: "@saltpepperskillet",
            ingredients: "2 salmon fillets\n2 tbsp honey\n3 garlic cloves, minced\n1 tbsp soy sauce\n1 tsp red pepper flakes\n1 tbsp olive oil\nScallions for garnish",
            estimatedCookingMinutes: 14,
            prepMinutes: 8,
            totalSteps: 4,
            notes: "Pan-sear skin side down first for extra crispiness.",
            stepsContent: "Pat salmon dry and season with salt and pepper.\nWhisk honey, garlic, soy sauce, and pepper flakes.\nSear salmon until golden, then spoon in sauce and baste.\nPlate and finish with scallions.",
            downloadedVideoURL: thumbnailPath,
            dishHeroTimestampSeconds: 1
        )
    }

    @MainActor
    static func makePreviewContainer() -> (ModelContainer, Recipe)? {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: Recipe.self, configurations: config)
            let ctx = ModelContext(container)
            let recipe = makeRecipe()
            ctx.insert(recipe)
            try ctx.save()
            return (container, recipe)
        } catch {
            return nil
        }
    }
}
