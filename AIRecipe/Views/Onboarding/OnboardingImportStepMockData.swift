import SwiftUI
import SwiftData

enum OnboardingImportStepMockData {
    /// Bundled hero images for import list rows (`RecipeListThumbnailView` reads `asset://` URLs).
    private static let salmonThumb = "asset://crispy"
    private static let steakThumb = "asset://steak"
    private static let wrapThumb = "asset://chicken"
    private static let pastaThumb = "asset://salmon"

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
                downloadedVideoURL: steakThumb,
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
                downloadedVideoURL: wrapThumb,
                dishHeroTimestampSeconds: 1
            )

            let extra3 = Recipe(
                ownerUserId: Recipe.localOnboardingOwnerPlaceholder,
                title: "Creamy Tuscan Pasta",
                source: .tiktok,
                sourceURL: "https://tiktok.com/@demo/video/3",
                creator: "@pastaparty",
                ingredients: "pasta\ncream\nsun-dried tomatoes\nspinach\nparmesan",
                estimatedCookingMinutes: 18,
                prepMinutes: 6,
                totalSteps: 4,
                stepsContent: "Boil pasta.\nSauté garlic.\nSimmer cream sauce.\nToss and serve.",
                downloadedVideoURL: pastaThumb,
                dishHeroTimestampSeconds: 1
            )

           

            let recipes = [base, extra1, extra2, extra3]
            recipes.forEach { ctx.insert($0) }
            try ctx.save()
            return (container, recipes)
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
            stepsContent: "Take the salmon out of the fridge about 15 minutes before cooking so it comes closer to room temperature. \n In a small bowl, whisk together the honey, soy sauce, and minced garlic to create your glaze. \n Pat the salmon fillets completely dry with a paper towel—this is crucial for getting a perfectly crispy skin and crust. \n Rub the salmon fillets with olive oil and generously season all sides with the paprika, salt, and pepper. \n Heat an oven-safe skillet (like cast iron) over medium-high heat. \n Once the skillet is hot, add the salmon fillets (skin-side down) and sear without moving for 3 to 4 minutes to build a beautiful golden-brown crust. \n Carefully flip the salmon over and sear for another 2 to 3 minutes, then remove the fillets from the pan and set aside on a plate. \n Keeping the heat on medium-low, pour your prepared honey garlic mixture directly into the hot skillet. \n Let the sauce bubble up and simmer for about 1 minute until it thickens into a glossy, sticky glaze. \n Turn off the heat, add the salmon back into the skillet, and use a spoon to generously baste the fillets in the glaze until fully coated. \n Garnish with sesame seeds and green onions, then serve immediately.",
            downloadedVideoURL: salmonThumb,
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
