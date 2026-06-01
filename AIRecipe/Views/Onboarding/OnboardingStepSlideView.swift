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
            OnboardingRecipeDoneNotificationSlideView()

        case .importTapRecipe, .importTapEdit, .importAddMinute, .importSaveEdits:
            OnboardingImportWalkthroughView(
                step: step.importCoachStep ?? .tapImportRow,
                onFlowCompleted: onImportTabFlowCompleted
            )

        case .recipePageTapSteps:
            OnboardingRecipePageStepsSlideView()

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

    @ViewBuilder
    private func screenshotSlide(for step: OnboardingStep) -> some View {
        if let asset = step.screenshotAssetName {
            OnboardingScreenshotSlideView(
                coach: step.coach,
                imageName: asset,
                systemImage: step.screenshotPlaceholderIcon
            )
        } else {
            EmptyView()
        }
    }
}

#Preview("Share") {
    OnboardingStepSlideView(step: .shareRecipe)
}
