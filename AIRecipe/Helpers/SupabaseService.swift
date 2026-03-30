import Foundation
import Supabase

/// Configuration for the Supabase client used for subscriptions and usage limits.
enum SupabaseConfig {
    static let url = URL(string: "https://bebnwgehuzvrkjoiszdi.supabase.co")!
    static let key = "sb_publishable_RVWEbkVAOtuDdLFJfF3cAA_KP21sv9C"
}

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
        #if DEBUG
        if SupabaseConfig.key.hasPrefix("sb_") || SupabaseConfig.key.count < 80 {
            print("SupabaseService: Supabase anon key looks invalid. Use the long anon key from Supabase Dashboard → Settings → API (starts with 'eyJ...').")
        }
        #endif
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.key
        )
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
    
    func useAIOnce() async throws {
        guard let userId = try? await client.auth.session.user.id else {
            throw SupabaseUsageError.notAuthenticated
        }
        struct Params: Encodable { let user_id: UUID }
        _ = try await client
            .rpc("use_ai_once", params: Params(user_id: userId))
            .execute()
    }

    /// Call the `use_export_once` RPC in Supabase to check and increment export usage.
    func useExportOnce() async throws {
        guard let userId = try? await client.auth.session.user.id else {
            throw SupabaseUsageError.notAuthenticated
        }
        struct Params: Encodable { let user_id: UUID }
        _ = try await client
            .rpc("use_export_once", params: Params(user_id: userId))
            .execute()
    }

    /// Deletes the signed-in user via GoTrue `DELETE /auth/v1/user` (removes `auth.users` and cascades to `profiles` if FK is set).
    func deleteAccount() async throws {
        let session: Session
        do {
            session = try await client.auth.session
        } catch {
            throw SupabaseAccountError.notAuthenticated
        }
        let url = SupabaseConfig.url.appendingPathComponent("auth/v1/user")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
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

    /// Update the user's subscription plan in the `profiles` table.
    func updatePlan(to plan: String) async throws {
        guard let userId = try? await client.auth.session.user.id else {
            throw SupabaseUsageError.notAuthenticated
        }

        struct ProfileUpdate: Encodable {
            let plan_type: String
        }

        _ = try await client
            .from("profiles")
            .update(ProfileUpdate(plan_type: plan))
            .eq("id", value:userId)
            .execute()
    }
}

