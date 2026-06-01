import SwiftUI

/// Step 4: mock share-extension card with “View Import Progress In App”.
struct SilentImportSlideView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                OnboardingCoachmark(text: OnboardingStep.viewImportInApp.coachmark)
                    .padding(.horizontal, 20)

                shareExtensionCard
                    .padding(.horizontal, 24)
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var shareExtensionCard: some View {
        VStack(spacing: 18) {
            Text("Import Successful!")
                .font(OnboardingMockUIFont.bitter(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)

            highlightedButton(title: "View Import Progress In App")
            plainButton(title: "Close")
        }
        .padding(22)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
        )
        .padding(.trailing, AppTheme.boxShadowOffset)
        .padding(.bottom, AppTheme.boxShadowOffset)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black)
        )
    }

    private func highlightedButton(title: String) -> some View {
        Text(title)
            .font(OnboardingMockUIFont.bitter(size: 16, weight: .heavy))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.primary, lineWidth: 3)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .offset(x: 6, y: -10)
            }
    }

    private func plainButton(title: String) -> some View {
        Text(title)
            .font(OnboardingMockUIFont.bitter(size: 16, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black, lineWidth: 2)
            )
    }
}

/// Bitter helper for onboarding mock UI (file-private, not inside the struct body).
fileprivate enum OnboardingMockUIFont {
    static func bitter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        AppTheme.bitterFont(size: size, weight: weight)
    }
}
