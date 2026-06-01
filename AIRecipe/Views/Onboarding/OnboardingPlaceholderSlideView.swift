import SwiftUI

/// Coachmark-only slide for steps not yet fully built.
struct OnboardingPlaceholderSlideView: View {
    let step: OnboardingStep

    var body: some View {
        VStack {
            Spacer(minLength: 24)
            OnboardingCoachmark(text: step.coachmark)
                .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
