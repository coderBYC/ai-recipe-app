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

/// Thin wrapper around SupabaseClient for user plan and usage counters.
final class SupabaseService {
    static let shared = SupabaseService()

    /// Single Supabase client used by the app.
    let client: SupabaseClient

    init() {
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
    
    func useAIOnce() async throws {
        struct EmptyParams: Encodable {}
        _ = try await client
            .rpc("use_ai_once", params: EmptyParams())
            .execute()
    }

    /// Call the `use_export_once` RPC in Supabase to check and increment export usage.
    func useExportOnce() async throws {
        struct EmptyParams: Encodable {}
        _ = try await client
            .rpc("use_export_once", params: EmptyParams())
            .execute()
    }

    /// Update the user's subscription plan in the `profiles` table.
    func updatePlan(to plan: String) async throws {
        guard let userId = try? await client.auth.session.user.id else {
            throw SupabaseUsageError.notAuthenticated
        }

        struct ProfileUpdate: Encodable { let plan_type: String }

        _ = try await client
            .from("profiles")
            .update(ProfileUpdate(plan_type: plan))
            .eq("id", value:userId)
            .execute()
    }
}

