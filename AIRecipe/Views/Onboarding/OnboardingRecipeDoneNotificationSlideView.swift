import SwiftUI
import UIKit

/// Slide 4 — salmon hero + iOS-style “recipe ready” push notification mock.
struct OnboardingRecipeDoneNotificationSlideView: View {
    private static let appDisplayName = "Let Him Cook"
    private static let appIconAsset = "icon"
    private static let heroImageAsset = "crispy"
    private static let heroImageFallback = "salmon"
    private static let notificationBody =
        "Your Crispy Honey Garlic Salmon Recipe is ready!"

    @State private var notificationRevealed = false
    @State private var didPlayHaptic = false

    private static let revealSpring = Animation.spring(response: 0.55, dampingFraction: 0.82)

    var body: some View {
        VStack(spacing: 16) {
            Text("④ Your Recipe Is Done!")
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .appFont(.title)

            heroSalmonImage
                .padding(.horizontal, 28)
                .padding(.top, 4)

            iosNotificationCard(revealed: notificationRevealed)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await runEntranceSequence()
        }
        .onDisappear {
            notificationRevealed = false
            didPlayHaptic = false
        }
    }

    @ViewBuilder
    private var heroSalmonImage: some View {
        let asset = UIImage(named: Self.heroImageAsset) != nil
            ? Self.heroImageAsset
            : Self.heroImageFallback

        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 280, maxHeight: 200)
            .accessibilityLabel("Crispy honey garlic salmon")
    }

    private func iosNotificationCard(revealed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                appIconView
                    .frame(width: 36, height: 36)

                Text(Self.appDisplayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("now")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(white: 0.55))
            }

            Text(Self.notificationBody)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.black)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(notificationCardFill)
                .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 5)
        }
        .scaleEffect(revealed ? 1 : 0.96, anchor: .top)
        .offset(y: revealed ? 0 : -28)
        .opacity(revealed ? 1 : 0)
        .animation(Self.revealSpring, value: revealed)
    }

    @ViewBuilder
    private var appIconView: some View {
        if UIImage(named: Self.appIconAsset) != nil {
            Image(Self.appIconAsset)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.65))
                }
        }
    }

    /// Light gray translucent card like the iOS banner in the mock.
    private var notificationCardFill: some ShapeStyle {
        Color(white: 0.94).opacity(0.96)
    }

    @MainActor
    private func runEntranceSequence() async {
        notificationRevealed = false
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }

        withAnimation(Self.revealSpring) {
            notificationRevealed = true
        }

        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled, !didPlayHaptic else { return }
        didPlayHaptic = true
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            OnboardingRecipeReadyHaptics.play()
        }
    }
}

// MARK: - Longer “notification arrived” haptic

enum OnboardingRecipeReadyHaptics {
    static func play() {
        let notification = UINotificationFeedbackGenerator()
        notification.prepare()
        notification.notificationOccurred(.success)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
        }
    }
}

#Preview {
    OnboardingRecipeDoneNotificationSlideView()
        .background(Color.white)
}
