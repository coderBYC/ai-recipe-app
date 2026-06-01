import SwiftUI

enum OnboardingMediaLayout {
    /// Portrait iPhone frame (390×844 pt) for screenshots and screen recordings.
    static let aspectRatio: CGFloat = 390 / 844
    static let horizontalPadding: CGFloat = 24
    static let cornerRadius: CGFloat = 12
}

/// Shared aspect-ratio frame with comic border and offset shadow.
struct OnboardingMediaBox<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Color.clear
            .aspectRatio(OnboardingMediaLayout.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                Color.black
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: OnboardingMediaLayout.cornerRadius))
            .onboardingMediaChrome()
    }
}

struct OnboardingMediaPlaceholder: View {
    let systemImage: String
    let message: String

    var body: some View {
        OnboardingMediaBox {
            Color(white: 0.96)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: systemImage)
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        Text(message)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }
        }
    }
}

extension View {
    func onboardingMediaChrome() -> some View {
        overlay(
            RoundedRectangle(cornerRadius: OnboardingMediaLayout.cornerRadius)
                .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
        )
        .padding(.trailing, AppTheme.boxShadowOffset)
        .padding(.bottom, AppTheme.boxShadowOffset)
        .background(
            RoundedRectangle(cornerRadius: OnboardingMediaLayout.cornerRadius)
                .fill(Color.black)
        )
    }
}
