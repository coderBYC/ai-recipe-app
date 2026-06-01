import SwiftUI
import SwiftData

/// Step 7: in-memory demo recipe edit (no cloud save).
struct RecipeEditOnboardingSlideView: View {
    @State private var recipe = OnboardingDemoRecipe.make()

    var body: some View {
        VStack(spacing: 12) {
            OnboardingCoachmark(OnboardingStep.importTapEdit.coach)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            RecipeEditView(recipe: recipe) { }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RecipeEditOnboardingSlideView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
