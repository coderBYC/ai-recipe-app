import SwiftUI
import SwiftData

/// Click Steps slide — steps card only (no phone frame, gray overlay, or coach).
struct OnboardingRecipePageStepsSlideView: View {
    @State private var previewContainer: ModelContainer?
    @State private var recipe: Recipe?

    var body: some View {
        VStack(spacing: 16) {
            Text(OnboardingStep.recipePageTapSteps.coach.text)
                .appFont(.titleBold)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
                .padding(.top, 12)

            if let recipe {
                OnboardingRecipeStepsSectionView(stepLines: recipe.stepLines)
                    .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
            } else {
                ProgressView()
                    .padding(.top, 40)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if previewContainer == nil, let pair = OnboardingImportStepMockData.makePreviewContainer() {
                previewContainer = pair.0
                recipe = pair.1
            }
        }
        .modifier(OnboardingPreviewModelContainer(container: previewContainer))
    }
}

private struct OnboardingPreviewModelContainer: ViewModifier {
    let container: ModelContainer?

    func body(content: Content) -> some View {
        if let container {
            content.modelContainer(container)
        } else {
            content
        }
    }
}

#Preview {
    OnboardingRecipePageStepsSlideView()
        .background(Color(.systemBackground))
}
