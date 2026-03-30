import Foundation
@Observable @MainActor
final class AuthManager: ObservableObject {
    private let service: SupabaseService
    var error: Error?
    var authState: AuthState = .notDetermined

    init(service: SupabaseService) {
        self.service = service
    }

    func login(withEmail email: String, password: String) async {
        do {
            self.authState = try await service.login(withEmail: email, password: password)
        } catch {
            self.error = error
            print("Error: \(error)")
        }
    }

    func signup(withEmail email: String, password: String) async {
        do {
            self.authState = try await service.signUp(withEmail: email, password: password)
        } catch {
            self.error = error
            print("Error: \(error)")
        }
    }

    func signOut() async {
        do {
            try await service.signOut()
            self.authState = .notAuthenticated
        } catch {
            print("Error: \(error)")
        }
    }

    /// Deletes the Supabase auth user (`DELETE /auth/v1/user`) and signs out locally.
    func deleteAccount() async throws {
        try await service.deleteAccount()
        self.authState = .notAuthenticated
    }

    func getAuthState() async {
        do {
            self.authState = try await service.getAuthState()
        } catch {
            print("Error: \(error)")
        }
    }
}
