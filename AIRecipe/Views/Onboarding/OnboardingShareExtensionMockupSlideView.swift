import SwiftUI

/// Onboarding slide after share — staged: title → arrow → card → loading → done → leave copy → notify copy.
struct OnboardingShareExtensionMockupSlideView: View {
    private enum SequenceStep: Int, Comparable {
        case title = 0
        case arrow
        case card
        case loading
        case loadingDone
        case leaveMessage
        case notification

        static func < (lhs: SequenceStep, rhs: SequenceStep) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    @State private var step: SequenceStep = .title
    @State private var cardPhase: OnboardingShareExtensionHandoffCard.Phase = .placeholder
    @State private var isRevealed = false

    private static let spring = Animation.spring(response: 0.62, dampingFraction: 0.82)

    var body: some View {
        VStack(spacing: 12) {
            Text("③ What You'll See After You Share")
                .appFont(.titleBold)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
                .padding(.top, 50)
                .shareSequenceVisible(step >= .title, isRevealed: isRevealed, order: 0)

            OnboardingFlashingArrowView(rotationDegrees: 60)
                .padding(.bottom, 25)
                .frame(height: 180)
                .shareSequenceVisible(step >= .arrow, isRevealed: isRevealed, order: 1)

            OnboardingShareExtensionHandoffCard(phase: cardPhase)
                .padding(.horizontal, 20)
                .shareSequenceVisible(step >= .card, isRevealed: isRevealed, order: 2)

            Text("You Can Leave And Keep Scrolling")
                .appFont(.titleBold)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
                .padding(.top, 50)
                .shareSequenceVisible(step >= .leaveMessage, isRevealed: isRevealed, order: 3)

            Text("🔔 Let Him Cook Will Notify You When It's Ready 🫵")
                .appFont(.titleBold)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
                .padding(.top, 20)
                .shareSequenceVisible(step >= .notification, isRevealed: isRevealed, order: 4)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await runEntranceSequence()
        }
        .onDisappear {
            step = .title
            cardPhase = .placeholder
            isRevealed = false
        }
    }

    @MainActor
    private func runEntranceSequence() async {
        step = .title
        cardPhase = .placeholder
        isRevealed = false

        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            step = .notification
            cardPhase = .success
            isRevealed = true
            return
        }

        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }
        withAnimation(Self.spring) { isRevealed = true }

        try? await Task.sleep(for: .milliseconds(520))
        guard !Task.isCancelled else { return }
        withAnimation(Self.spring) { step = .arrow }

        try? await Task.sleep(for: .milliseconds(520))
        guard !Task.isCancelled else { return }
        withAnimation(Self.spring) { step = .card }

        try? await Task.sleep(for: .milliseconds(480))
        guard !Task.isCancelled else { return }
        withAnimation(Self.spring) {
            step = .loading
            cardPhase = .grabbing
        }

        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            cardPhase = .sending
        }

        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        withAnimation(Self.spring) {
            step = .loadingDone
            cardPhase = .success
        }

        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }
        withAnimation(Self.spring) { step = .leaveMessage }

        try? await Task.sleep(for: .milliseconds(580))
        guard !Task.isCancelled else { return }
        withAnimation(Self.spring) { step = .notification }
    }
}

// MARK: - Staggered reveal

private struct ShareSequenceVisibleModifier: ViewModifier {
    let isVisible: Bool
    let isRevealed: Bool
    let order: Int

    private var delay: Double { Double(order) * 0.06 }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible && isRevealed ? 1 : 0)
            .offset(y: isVisible && isRevealed ? 0 : -20)
            .animation(
                .spring(response: 0.62, dampingFraction: 0.82).delay(isVisible ? delay : 0),
                value: isRevealed
            )
            .animation(.spring(response: 0.62, dampingFraction: 0.82), value: isVisible)
    }
}

private extension View {
    func shareSequenceVisible(_ isVisible: Bool, isRevealed: Bool, order: Int) -> some View {
        modifier(ShareSequenceVisibleModifier(isVisible: isVisible, isRevealed: isRevealed, order: order))
    }
}

#Preview {
    OnboardingShareExtensionMockupSlideView()
        .background(Color(.systemBackground))
}
