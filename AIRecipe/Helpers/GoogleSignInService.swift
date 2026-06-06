import Foundation
import UIKit
import GoogleSignIn
import Auth
import Supabase

enum GoogleSignInError: LocalizedError {
    case missingIOSClientID
    case missingWebClientID
    case noPresentingViewController
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .missingIOSClientID:
            return "Google Sign-In is not configured (GIDClientID missing in Info.plist)."
        case .missingWebClientID:
            return """
            Google Sign-In needs your Web OAuth Client ID.
            Add GOOGLE_WEB_CLIENT_ID to Config/AppSecrets.local.xcconfig (same Web client ID configured in Supabase Auth → Google), then Clean Build Folder.
            """
        case .noPresentingViewController:
            return "Could not present Google Sign-In (no active window)."
        case .missingIDToken:
            return "Google Sign-In did not return an ID token. Set GOOGLE_WEB_CLIENT_ID to your Web OAuth client ID from Google Cloud Console."
        }
    }
}

enum GoogleSignInService {
    static func configure() {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            #if DEBUG
            print("GoogleSignInService: GIDClientID missing from Info.plist")
            #endif
            return
        }
        let iosClientID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !iosClientID.isEmpty else { return }

        let webClientID = AppSecrets.googleWebClientID
        if webClientID.isEmpty {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: iosClientID)
            #if DEBUG
            print("GoogleSignInService: GOOGLE_WEB_CLIENT_ID missing — Supabase sign-in requires serverClientID.")
            #endif
        } else {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: iosClientID,
                serverClientID: webClientID
            )
        }
    }

    @MainActor
    static func signInWithSupabase() async throws {
        if GIDSignIn.sharedInstance.configuration == nil {
            configure()
        }

        guard !AppSecrets.googleWebClientID.isEmpty else {
            throw GoogleSignInError.missingWebClientID
        }

        guard let presenter = topViewController() else {
            throw GoogleSignInError.noPresentingViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)

        guard let idToken = result.user.idToken?.tokenString else {
            throw GoogleSignInError.missingIDToken
        }

        let accessToken = result.user.accessToken.tokenString
        try await SupabaseService.shared.client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken
            )
        )
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first else {
            return nil
        }

        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
