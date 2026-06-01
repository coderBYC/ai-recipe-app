import SwiftUI

/// Step 5: simulated “recipe ready” notification.
struct NotificationSimulatedSlideView: View {
    @Binding var showBanner: Bool

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 16) {
                Spacer(minLength: 8)
                OnboardingCoachmark(text: OnboardingStep.recipeDoneNotification.coachmark)
                    .padding(.horizontal, 20)
                Spacer()
            }

            if showBanner {
                notificationBanner
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showBanner)
    }

    private var notificationBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "frying.pan.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 36, height: 36)
                .background(AppTheme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Let Him Cook")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                Text("Your recipe is ready!")
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("One-Pan Garlic Noodles · Imports")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("now")
                .appFont(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
    }
}
