import SwiftUI
import UIKit

/// iOS-style stacked push notification mock for the “recipe ready” onboarding step.
struct OnboardingRecipeDoneNotificationSlideView: View {
    private static let appDisplayName = "Let Him Cook"
    private static let appIconAsset = "icon"

    @State private var stackRevealed = false
    @State private var didPlayHaptic = false

    private static let stackSpring = Animation.spring(response: 0.62, dampingFraction: 0.78)
    private static let cardSpring = Animation.spring(response: 0.55, dampingFraction: 0.82)

    var body: some View {
        VStack(spacing: 20) {
            Text("④ Your Recipe Is Done!")
                .padding(.horizontal, 20)
                .appFont(.title)

            VStack(spacing: 6) {
                primaryNotificationCard(revealed: stackRevealed)
                stackedNotificationCard(layer: .middle, revealed: stackRevealed)
                stackedNotificationCard(layer: .back, revealed: stackRevealed)
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await runEntranceSequence()
        }
        .onDisappear {
            stackRevealed = false
            didPlayHaptic = false
        }
    }

    private enum StackLayer {
        case back
        case middle

        var scale: CGFloat {
            switch self {
            case .back: return 0.9
            case .middle: return 0.95
            }
        }

        var horizontalInset: CGFloat {
            switch self {
            case .back: return 14
            case .middle: return 7
            }
        }

        var opacity: Double {
            switch self {
            case .back: return 0.5
            case .middle: return 0.68
            }
        }

        var entranceDelay: Double {
            switch self {
            case .back: return 0.2
            case .middle: return 0.12
            }
        }
    }

    private func stackedNotificationCard(layer: StackLayer, revealed: Bool) -> some View {
        glassPlate(cornerRadius: 20, materialOpacity: layer.opacity)
            .frame(height: 44)
            .padding(.horizontal, layer.horizontalInset)
            .scaleEffect(revealed ? layer.scale : layer.scale * 0.94, anchor: .top)
            .offset(y: revealed ? 0 : -12)
            .opacity(revealed ? 1 : 0)
            .animation(Self.stackSpring.delay(layer.entranceDelay), value: revealed)
    }

    private func primaryNotificationCard(revealed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                appIconView
                    .frame(width: 28, height: 28)

                Text(Self.appDisplayName.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(notificationInk)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("now")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(notificationInk.opacity(0.55))
            }
            .padding(.bottom, 8)

            Text("Your Crispy Salmon Recipe Is Ready!")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(notificationInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            glassPlate(cornerRadius: 22, materialOpacity: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 20, y: 10)
        .scaleEffect(revealed ? 1 : 0.94, anchor: .top)
        .offset(y: revealed ? 0 : -40)
        .opacity(revealed ? 1 : 0)
        .animation(Self.cardSpring.delay(0.04), value: revealed)
    }

    @ViewBuilder
    private var appIconView: some View {
        if UIImage(named: Self.appIconAsset) != nil {
            Image(Self.appIconAsset)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(notificationInk.opacity(0.12))
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(notificationInk.opacity(0.7))
                }
        }
    }

    private func glassPlate(cornerRadius: CGFloat, materialOpacity: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.12 * materialOpacity))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(materialOpacity)
            }
            .glassStroke(cornerRadius: cornerRadius)
    }

    private var notificationInk: Color {
        Color.primary.opacity(0.88)
    }

    @MainActor
    private func runEntranceSequence() async {
        stackRevealed = false
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }

        withAnimation(Self.stackSpring) {
            stackRevealed = true
        }

        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled, !didPlayHaptic else { return }
        didPlayHaptic = true
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            OnboardingRecipeReadyHaptics.play()
        }
    }
}

// MARK: - Glass chrome

private extension View {
    func glassStroke(cornerRadius: CGFloat) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
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
        .background {
            LinearGradient(
                colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
}
