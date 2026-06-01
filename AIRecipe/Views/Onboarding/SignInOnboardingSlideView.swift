import SwiftUI
import AuthenticationServices

struct SignInOnboardingSlideView: View {
    var onAuthenticated: () -> Void
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        VStack(spacing: 16) {
            OnboardingCoachmark(OnboardingStep.signInAuth.coach)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            LoginView(
                onSignedIn: { _ in onAuthenticated() },
                onError: { _ in },
                embedInNavigationStack: false
            )
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: authManager.authState) { _, state in
            if state == .authenticated {
                onAuthenticated()
            }
        }
        .onAppear {
            if authManager.authState == .authenticated {
                onAuthenticated()
            }
        }
    }
}

#Preview {
    SignInOnboardingSlideView(onAuthenticated: {})
        .environment(AuthManager(service: SupabaseService.shared))
}
