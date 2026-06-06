import SwiftUI
import Auth
import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift
import Supabase


struct LoginView: View {
    let onSignedIn: (ASAuthorizationAppleIDCredential) -> Void
    let onError: (Error) -> Void
    /// When false, parent supplies navigation chrome (e.g. onboarding sign-in slide).
    var embedInNavigationStack: Bool = true
    @State private var showEmailMagicLinkSheet = false
    @Environment(AuthManager.self) private var authManager

    private var authErrorMessage: Binding<String?> {
        Binding(
            get: { authManager.error?.localizedDescription },
            set: { if $0 == nil { authManager.error = nil } }
        )
    }

    var body: some View {
        loginContent
            .errorPopup(message: authErrorMessage)
            .sheet(isPresented: $showEmailMagicLinkSheet) {
                MagicLinkEmailSheet(onError: onError)
                    .environment(authManager)
            }
    }

    private var loginContent: some View {
        VStack {
            Spacer()
            Image("icon")
                .resizable()
                .scaledToFit()
                .cornerRadius(20)
                .frame(width: 100, height: 100)
                .padding(.bottom, 20)

            Text("Let Him Cook")
                .nanumAppFont(.largeTitle)
                .fontWeight(.bold)
            Text("Viral Reels To Recipe")
                .nanumAppFont(.title2)
                .padding(.bottom, 60)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                Task {
                    do {
                        switch result {
                        case .success(let authorization):
                            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                               let idToken = appleIDCredential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) {
                                try await SupabaseService.shared.client.auth.signInWithIdToken(
                                    credentials: .init(provider: .apple, idToken: idToken)
                                )

                                if let name = appleIDCredential.fullName {
                                    let firstName = name.givenName ?? ""
                                    let lastName = name.familyName ?? ""

                                    let attributes = UserAttributes(
                                        data: [
                                            "first_name": .string(firstName),
                                            "last_name": .string(lastName)
                                        ]
                                    )

                                    try await SupabaseService.shared.client.auth.update(user: attributes)
                                }

                                await authManager.getAuthState()
                            }
                        case .failure(let error):
                            authManager.error = error
                            onError(error)
                        }
                    } catch {
                        authManager.error = error
                        onError(error)
                    }
                }
            }
            .frame(width: 300, height: 54)

            CustomGoogleButton(
                width: 300,
                height: 54,
                fontSize: 20,
                cornerRadius: 10,
                iconSize: 22
            ) {
                Task {
                    do {
                        try await GoogleSignInService.signInWithSupabase()
                        await authManager.getAuthState()
                    } catch {
                        authManager.error = error
                        onError(error)
                    }
                }
            }
            .padding()

            Text("— OR —")
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.vertical, 2)

            Button {
                showEmailMagicLinkSheet = true
            } label: {
                HStack {
                    Image(systemName: "envelope")
                        .foregroundColor(.black)
                    Text("Continue with email")
                        .appFont(.title3)
                }
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.black, lineWidth: 2)
                )
                .frame(width: 300, height: 54)

            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 190)
    }
}

// MARK: - Magic link email sheet

private struct MagicLinkEmailSheet: View {
    let onError: (Error) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager

    @State private var emailInput = ""
    @State private var isSendingMagicLink = false
    @State private var linkSent = false
    @State private var resendSecondsRemaining = 0

    private let resendCooldownSeconds = 60
    private static let magicLinkRedirect = URL(string: "io.supabase.user-management://login-callback")!

    private var trimmedEmail: String {
        emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        trimmedEmail.contains("@") && !isSendingMagicLink && resendSecondsRemaining == 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(linkSent
                     ? "We sent a sign-in link to your inbox. Tap it on this device to continue."
                     : "Enter your email and we’ll send you a one-time sign-in link.")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                TextField("Email address", text: $emailInput)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(AppTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.black, lineWidth: AppTheme.boxBorderWidth)
                    )
                    .disabled(linkSent)
                    .opacity(linkSent ? 0.7 : 1)

                if linkSent {
                    sentLinkActions
                } else {
                    sendLinkButton
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .navigationTitle("Sign in with email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: authManager.authState) { _, state in
                if state == .authenticated {
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var sendLinkButton: some View {
        Button {
            sendMagicLink()
        } label: {
            HStack {
                if isSendingMagicLink {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Send magic link")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(canSend ? AppTheme.primary : Color.gray.opacity(0.45))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!canSend)
    }

    private var sentLinkActions: some View {
        VStack(spacing: 12) {
            Button {
                openEmailApp()
            } label: {
                Text("Open Email")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(AppTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                sendMagicLink()
            } label: {
                Group {
                    if isSendingMagicLink {
                        ProgressView()
                    } else if resendSecondsRemaining > 0 {
                        Text("Resend link in \(resendSecondsRemaining)s")
                    } else {
                        Text("Resend link")
                    }
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(AppTheme.cardBackground)
                .foregroundStyle(resendSecondsRemaining > 0 ? AppTheme.textSecondary : AppTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(AppTheme.primary, lineWidth: AppTheme.boxBorderWidth)
                )
            }
            .disabled(isSendingMagicLink || resendSecondsRemaining > 0)
        }
    }

    /// Lives on `MagicLinkEmailSheet` so it can access `@State` and `authManager`.
    private func sendMagicLink() {
        guard canSend || (linkSent && resendSecondsRemaining == 0 && !isSendingMagicLink) else { return }

        isSendingMagicLink = true
        Task {
            do {
                try await SupabaseService.shared.client.auth.signInWithOTP(
                    email: trimmedEmail,
                    redirectTo: Self.magicLinkRedirect
                )
                await MainActor.run {
                    isSendingMagicLink = false
                    linkSent = true
                    startResendCooldown()
                }
            } catch {
                await MainActor.run {
                    isSendingMagicLink = false
                    authManager.error = error
                    onError(error)
                }
            }
        }
    }

    private func startResendCooldown() {
        resendSecondsRemaining = resendCooldownSeconds
        Task {
            while !Task.isCancelled, resendSecondsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    if resendSecondsRemaining > 0 {
                        resendSecondsRemaining -= 1
                    }
                }
            }
        }
    }

    private func openEmailApp() {
        let candidates = ["message://", "mailto:"]
        for raw in candidates {
            guard let url = URL(string: raw), UIApplication.shared.canOpenURL(url) else { continue }
            UIApplication.shared.open(url)
            return
        }
    }
}

#Preview {
    LoginView(onSignedIn: { _ in }, onError: { _ in })
        .environment(AuthManager(service: SupabaseService.shared))
}

struct CustomGoogleButton: View {
    var width: CGFloat? = .infinity
    var height: CGFloat = 54
    var fontSize: CGFloat = 25
    var cornerRadius: CGFloat = 12
    var iconSize: CGFloat = 10

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image("google")
                    .resizable()
                    .frame(width: iconSize, height: iconSize)

                Text("Sign in with Google")
                    .font(.system(size: fontSize, weight: .medium, design: .default))
                    .foregroundColor(Color(red: 0.235, green: 0.251, blue: 0.263))
            }
            .padding(.horizontal, 16)
            .frame(width: width)
            .frame(height: height)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.gray, lineWidth: 2)
            )
        }
        .cornerRadius(5)
        .buttonStyle(GooglePressEffectStyle())
    }
}

struct GooglePressEffectStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(white: 0.96) : Color.clear)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
