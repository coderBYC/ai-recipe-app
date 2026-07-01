import RevenueCatUI
import SwiftUI

enum ProFeatureGate {
    static let unlockMessage = "Unlock With Let Him Cook Pro"

    /// Posts to MainView; prefer a local `.proPaywallSheet` when already inside a presented sheet.
    static func presentPaywall() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .presentRevenueCatPaywall, object: nil)
        }
    }
}

extension View {
    /// Presents RevenueCat paywall from the current view (works inside nested sheets).
    func proPaywallSheet(isPresented: Binding<Bool>, onUnlocked: (() -> Void)? = nil) -> some View {
        sheet(isPresented: isPresented) {
            RevenueCatUI.PaywallView(displayCloseButton: true)
                .onRequestedDismissal {
                    isPresented.wrappedValue = false
                }
                .onPurchaseCompleted { _, _ in
                    Task { @MainActor in
                        await SubscriptionManager.shared.refreshAndSyncPlan()
                        isPresented.wrappedValue = false
                        onUnlocked?()
                    }
                }
                .onRestoreCompleted { _ in
                    Task { @MainActor in
                        await SubscriptionManager.shared.refreshAndSyncPlan()
                        isPresented.wrappedValue = false
                        onUnlocked?()
                    }
                }
        }
    }
}

/// Blurs content and shows an unlock prompt for free users.
struct ProLockedOverlay<Content: View>: View {
    let isLocked: Bool
    var message: String
    var onUnlock: () -> Void
    @ViewBuilder var content: () -> Content

    init(
        isLocked: Bool,
        message: String = ProFeatureGate.unlockMessage,
        onUnlock: @escaping () -> Void = ProFeatureGate.presentPaywall,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLocked = isLocked
        self.message = message
        self.onUnlock = onUnlock
        self.content = content
    }

    var body: some View {
        ZStack {
            content()
                .blur(radius: isLocked ? 9 : 0)
                .allowsHitTesting(!isLocked)

            if isLocked {
                Button(action: onUnlock) {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.primary)
                        Text(message)
                            .appFont(.headlineBold)
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }
}
