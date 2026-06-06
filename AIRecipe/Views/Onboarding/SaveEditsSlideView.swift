import SwiftUI

/// Step 8: highlight saving edits in the edit screen.
struct SaveEditsSlideView: View {
    var body: some View {
        OnboardingScreenshotSlideView(
            coachmark: OnboardingStep.recipePageTapSteps.coachmark,
            imageName: "screenshot-save-edits",
            systemImage: "checkmark.circle"
        )
    }
}
