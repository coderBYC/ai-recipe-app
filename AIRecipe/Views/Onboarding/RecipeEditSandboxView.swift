import SwiftUI

/// Step 7: recipe page with edit sheet opened (sandbox, in-memory recipe).
struct RecipeEditSandboxView: View {
    @Bindable var recipe: Recipe

    var body: some View {
        VStack(spacing: 0) {
            OnboardingCoachmark(text: OnboardingStep.importTapEdit.coachmark)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 6)

            RecipePageView(
                recipe: recipe,
                onDismiss: {},
                openEditOnAppear: true
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
