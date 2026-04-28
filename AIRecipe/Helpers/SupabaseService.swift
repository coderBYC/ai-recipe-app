import Foundation
import Supabase

/// Errors specific to Supabase usage/plan handling.
enum SupabaseUsageError: Error {
    case notAuthenticated
    case sdkNotConfigured
}

enum SupabaseAccountError: Error, LocalizedError {
    case notAuthenticated
    case deleteFailed(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not signed in."
        case .deleteFailed(let status, let body):
            return "Could not delete account (HTTP \(status)): \(body)"
        }
    }
}

/// Thin wrapper around SupabaseClient for user plan and usage counters.
final class SupabaseService {
    static let shared = SupabaseService()

    /// Single Supabase client used by the app.
    let client: SupabaseClient

    init() {
        guard let url = AppSecrets.supabaseURL, !AppSecrets.supabaseAnonKey.isEmpty else {
            fatalError(AppSecrets.configurationHint)
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: AppSecrets.supabaseAnonKey)
    }

    func login(withEmail email:String, password: String) async throws -> AuthState{
        try await client.auth.signIn(email: email, password: password)
        return .authenticated
    }
    
    func signOut() async throws{
        try await client.auth.signOut()
    }
    
    func signUp(withEmail email:String, password: String) async throws -> AuthState{
        let response = try await client.auth.signUp(email: email, password: password)
        // If email confirmation is enabled, user exists but session may be nil
        if response.session != nil {
            return .authenticated
        }
        // User created but needs email confirmation
        return .notAuthenticated
    }
    
    func getAuthState() async throws -> AuthState{
        let user = try? await client.auth.session.user
        return user == nil ? .notAuthenticated : .authenticated
    }

    /// Supabase auth user id for API headers (e.g. recipe backend `X-User-Id`).
    func currentUserIdString() async -> String? {
        guard let userId = try? await client.auth.session.user.id else { return nil }
        return userId.uuidString
    }
    
    /// Deletes the signed-in user via GoTrue `DELETE /auth/v1/user` (removes `auth.users` and cascades to `profiles` if FK is set).
    func deleteAccount() async throws {
        let session: Session
        do {
            session = try await client.auth.session
        } catch {
            throw SupabaseAccountError.notAuthenticated
        }
        guard let base = AppSecrets.supabaseURL else {
            throw SupabaseAccountError.deleteFailed(status: 0, body: "Supabase URL not configured.")
        }
        let url = base.appendingPathComponent("auth/v1/user")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(AppSecrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAccountError.deleteFailed(status: 0, body: "No HTTP response")
        }
        if !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseAccountError.deleteFailed(status: http.statusCode, body: body)
        }

        try await client.auth.signOut()
    }

    /// Free-tier AI generations already completed (matches `use_ai_once` / backend quota). Next attempt should show paywall when not Pro.
    func fetchAIUsageCount() async throws -> Int {
        guard let userId = try? await client.auth.session.user.id else {
            throw SupabaseUsageError.notAuthenticated
        }

        struct Row: Decodable {
            let ai_usage_count: Int?
        }

        let row: Row = try await client
            .from("profiles")
            .select("ai_usage_count")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        return row.ai_usage_count ?? 0
    }
}

