import SwiftUI
import UIKit

struct OnboardingScreenshotSlideView: View {
    var coach: OnboardingCoachSpec
    let imageName: String
    let systemImage: String

    init(coach: OnboardingCoachSpec, imageName: String, systemImage: String) {
        self.coach = coach
        self.imageName = imageName
        self.systemImage = systemImage
    }

    init(coachmark text: String, imageName: String, systemImage: String) {
        self.coach = OnboardingCoachSpec(text: text)
        self.imageName = imageName
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: 20) {
            OnboardingCoachmark(coach)
                .padding(.horizontal, 20)

            screenshotContent
                .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var screenshotContent: some View {
        if UIImage(named: imageName) != nil {
            OnboardingMediaBox {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            OnboardingMediaPlaceholder(
                systemImage: systemImage,
                message: "Add “\(imageName)” to Assets"
            )
        }
    }
}

#Preview {
    OnboardingScreenshotSlideView(
        coach: OnboardingStep.shareRecipe.coach,
        imageName: "screenshot-share-sheet",
        systemImage: "square.and.arrow.up"
    )
}
