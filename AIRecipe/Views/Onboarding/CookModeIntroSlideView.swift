import SwiftUI

/// Step 9: intro to cook mode + button to open full preview.
struct CookModeIntroSlideView: View {
    var onOpenCookMode: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                OnboardingCoachmark(text: OnboardingStep.cookModeVoiceIntro.coachmark)
                    .padding(.horizontal, 20)

                cookModePreview
                    .padding(.horizontal, 20)

                Button(action: onOpenCookMode) {
                    Label("Open Cook Mode", systemImage: "flame.fill")
                        .appFont(.headlineBold)
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .boxStyle(cornerRadius: 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var cookModePreview: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i == 0 ? Color.white : Color.gray.opacity(0.4))
                        .frame(height: 6)
                }
            }
            .padding(.horizontal)

            Text("Toss noodles with garlic butter, pasta water, and parmesan.")
                .appFont(.title3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Text("5:00")
                .font(AppTheme.bitterFont(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text("1 / 4")
                .appFont(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
        )
    }
}
