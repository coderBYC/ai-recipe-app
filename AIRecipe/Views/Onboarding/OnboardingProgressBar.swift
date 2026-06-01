import SwiftUI

/// Segment progress for onboarding slides.
struct OnboardingProgressBar: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<OnboardingStep.stepCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index <= currentStep.rawValue ? Color.black : Color.black.opacity(0.15))
                    .frame(height: 6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }
}

#Preview {
    VStack {
        OnboardingProgressBar(currentStep: .intro)
        OnboardingProgressBar(currentStep: .shareRecipe)
    }
}
