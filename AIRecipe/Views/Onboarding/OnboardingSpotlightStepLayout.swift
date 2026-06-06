import SwiftUI

private enum OnboardingSpotlightStepLayoutMetrics {
    static let grayOpacity: Double = 0.78
    static let reveal = Animation.easeInOut(duration: 0.45)
}

/// Top headline + full recipe UI + gray spotlight cutout + flashing 👇 on the target control.
struct OnboardingSpotlightStepLayout<Content: View>: View {
    let headline: String
    let target: OnboardingSpotlightTarget
    @ViewBuilder var content: () -> Content

    @State private var targetRects: [OnboardingSpotlightTarget: CGRect] = [:]
    @State private var showSpotlight = false

    var body: some View {
        VStack(spacing: 8) {
            Text(headline)
                .appFont(.titleBold)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
                .padding(.top, 10)

            ZStack {
                content()
                    .coordinateSpace(name: OnboardingSpotlightCoordinateSpace.name)

                if showSpotlight, let rect = targetRects[target], rect.width > 2, rect.height > 2 {
                    spotlightOverlay(cutout: rect)

                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: OnboardingMediaLayout.cornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(OnboardingSpotlightTargetRectKey.self) { rects in
            targetRects = rects
        }
        .onAppear {
            showSpotlight = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(OnboardingSpotlightStepLayoutMetrics.reveal) {
                    showSpotlight = true
                }
            }
        }
        .onDisappear {
            showSpotlight = false
        }
    }

    private func spotlightOverlay(cutout: CGRect) -> some View {
        GeometryReader { proxy in
            let padded = cutout.insetBy(dx: -6, dy: -6)
            ZStack {
                Color.gray.opacity(OnboardingSpotlightStepLayoutMetrics.grayOpacity)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .frame(width: padded.width, height: padded.height)
                    .position(x: padded.midX - 20, y: padded.midY - 130)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .allowsHitTesting(false)
        }
    }
}
