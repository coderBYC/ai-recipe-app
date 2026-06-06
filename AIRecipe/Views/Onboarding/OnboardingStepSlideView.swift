import SwiftUI
import SwiftData

/// Renders the correct UI for each onboarding step.
struct OnboardingStepSlideView: View {
    let step: OnboardingStep
    var onAuthenticated: () -> Void = {}
    var onImportTabFlowCompleted: () -> Void = {}
    var onCookModeVoiceDemoCompleted: () -> Void = {}

    var body: some View {
        switch step {
        case .intro:
            IntroSlideView()
        case .shareRecipe:
            ShareButtonSlideView()
        case .viewImportInApp:
            OnboardingShareExtensionMockupSlideView()
        case .recipeDoneNotification:
            OnboardingRecipeDoneNotificationSlideView(onNotificationTapped: onImportTabFlowCompleted)

        case .importTapRecipe:
            OnboardingImportWalkthroughView(
                step: step.importCoachStep ?? .tapImportRow,
                onFlowCompleted: onImportTabFlowCompleted
            )

        case .importedRecipeShowcase:
            OnboardingImportedRecipeShowcaseSlideView()

        case .recipePageTapSteps:
            OnboardingRecipePageStepsSlideView(onStepsTapped: onImportTabFlowCompleted)

        case .cookModeVoiceIntro:
            OnboardingCookModeIntroSlideView(onVoiceDemoCompleted: onCookModeVoiceDemoCompleted)

        case .mealPlanAddRecipe:
            OnboardingMealPlanMockupSlideView(onRecipeSelected: onImportTabFlowCompleted)
        case .youAreDone:
            FinalCTASlideView()
        case .signInAuth:
            SignInOnboardingSlideView(onAuthenticated: onAuthenticated)
        }
    }
}

#Preview("Share") {
    OnboardingStepSlideView(step: .shareRecipe)
}
