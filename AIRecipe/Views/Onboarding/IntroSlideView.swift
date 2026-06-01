import SwiftUI

struct IntroSlideView: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 20)

            VStack(spacing: 8) {
                Text("Let Him Cook")
                    .appFont(.largeTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Viral reels → real recipes")
                    .appFont(.title3)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            OnboardingCoachmark(text: OnboardingStep.intro.coachmark)
                .padding(.horizontal, 20)

            Image(systemName: "frying.pan.fill")
                .font(.system(size: 72, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
