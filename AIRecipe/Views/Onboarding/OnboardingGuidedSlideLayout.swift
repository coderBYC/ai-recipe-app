import SwiftUI

/// Hand-drawn arrow asset with a pulsing opacity animation (use in slide layouts).
struct OnboardingFlashingArrowView: View {
    var imageName: String = "arrow"
    var rotationDegrees: Double = 90
    var width: CGFloat = 150
    var height: CGFloat = 100

    @State private var isVisible = false

    var body: some View {
        Group {
            if UIImage(named: imageName) != nil {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(rotationDegrees))
        .opacity(isVisible ? 1 : 0.18)
        .animation(
            .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
            value: isVisible
        )
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingFlashingArrowView(rotationDegrees: 70)
        .padding()
}
