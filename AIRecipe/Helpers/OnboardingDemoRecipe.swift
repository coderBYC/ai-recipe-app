import Foundation

enum OnboardingDemoRecipe {
    static func make() -> Recipe {
        Recipe(
            ownerUserId: Recipe.localOnboardingOwnerPlaceholder,
            title: "One-Pan Garlic Noodles",
            source: .tiktok,
            sourceURL: "https://www.tiktok.com/@demo/video/0",
            creator: "@chef_demo",
            ingredients: """
            8 oz spaghetti
            4 cloves garlic, minced
            2 tbsp butter
            1/4 cup parmesan
            Salt & pepper
            """,
            estimatedCookingMinutes: 15,
            prepMinutes: 5,
            totalSteps: 4,
            stepsContent: """
            Boil pasta until al dente; reserve 1/2 cup pasta water.
            Sauté garlic in butter until fragrant.
            Toss pasta with garlic butter, parmesan, and pasta water.
            Season and serve immediately.
            """
        )
    }
}
