import SwiftUI

/// Mirrors `ShareViewController` card UI: spinner + status, then success buttons (no sheet chrome).
struct OnboardingShareExtensionHandoffCard: View {
    enum Phase: Equatable {
        case placeholder
        case grabbing
        case sending
        case success
    }

    var phase: Phase

    var body: some View {
        VStack(spacing: 18) {
            if phase != .placeholder {
                Text(statusText)
                    .font(AppTheme.bitterFont(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if showsSpinner {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.black)
                    .frame(height: 28)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            if phase == .success {
                primaryButton(title: "View Import Progress In App")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                secondaryButton(title: "Close")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: phase)
        .padding(.horizontal, 18)
        .padding(.vertical, phase == .placeholder ? 28 : 22)
        .frame(maxWidth: .infinity)
        .frame(minHeight: phase == .placeholder ? 88 : nil)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black, lineWidth: 2)
        )
        .padding(.trailing, 5)
        .padding(.bottom, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)
        )
    }

    private var showsSpinner: Bool {
        phase == .grabbing || phase == .sending
    }

    private var statusText: String {
        switch phase {
        case .placeholder:
            return ""
        case .grabbing:
            return "Grabbing your link…"
        case .sending:
            return "Sending Recipe to Let Him Cook ..."
        case .success:
            return "Import Successful!"
        }
    }

    private func primaryButton(title: String) -> some View {
        Text(title)
            .font(AppTheme.nanumMyeongjoFont(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 14)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black, lineWidth: 2)
            )
    }

    private func secondaryButton(title: String) -> some View {
        Text(title)
            .font(AppTheme.bitterFont(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black, lineWidth: 2)
            )
    }
}

#Preview("Success") {
    OnboardingShareExtensionHandoffCard(phase: .success)
        .padding(24)
}
