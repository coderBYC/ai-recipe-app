import SwiftUI

struct OnboardingNavigationBar: View {
    @Binding var currentStep: OnboardingStep
    var onNext: () -> Void
    var onBack: () -> Void

    private var isFirstStep: Bool { currentStep == .intro }
    private var showsNextButton: Bool { !currentStep.isSignInStep }

    private var nextTitle: String {
        switch currentStep {
        case .youAreDone:
            return "Continue"
        case .signInAuth:
            return "Finish"
        default:
            return "Next"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            onboardingNavButton(title: "Back", enabled: !isFirstStep) {
                onBack()
            }

            if showsNextButton {
                onboardingNavButton(title: nextTitle, enabled: true) {
                    onNext()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppTheme.surface)
    }

    private func onboardingNavButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard enabled else { return }
            action()
        } label: {
            Text(title)
                .appFont(.headlineBold)
                .foregroundStyle(enabled ? AppTheme.textPrimary : AppTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .boxStyle(cornerRadius: 8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}
