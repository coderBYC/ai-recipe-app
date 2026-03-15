import Foundation
import Supabase
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://bebnwgehuzvrkjoiszdi.supabase.co")!,
    supabaseKey: "sb_publishable_RVWEbkVAOtuDdLFJfF3cAA_KP21sv9C"
)
/// Errors specific to Supabase usage/plan handling.
enum SupabaseUsageError: Error {
    case notAuthenticated
    case sdkNotConfigured
}

/// Thin wrapper around SupabaseClient for user plan and usage counters.
final class SupabaseService {
    static let shared = SupabaseService()
    private let client: SupabaseClient?
    private init(){
        
    }

    /// Call the `use_ai_once` RPC in Supabase to check and increment AI usage.
    func useAIOnce() async throws {
        guard client != nil else {
            throw SupabaseUsageError.sdkNotConfigured
        }
        struct EmptyParams: Encodable {}
        try await client?.rpc("use_ai_once", params: EmptyParams()).execute()
    }

    /// Call the `use_export_once` RPC in Supabase to check and increment export usage.
    func useExportOnce() async throws {
        guard client != nil else {
            throw SupabaseUsageError.sdkNotConfigured
        }
        // After adding the SDK, replace with:
        //
        // struct EmptyParams: Encodable {}
        // try await client.rpc("use_export_once", params: EmptyParams()).execute()
    }

    /// Update the user's subscription plan in the `profiles` table.
    func updatePlan(to plan: String) async throws {
        guard client != nil else {
            throw SupabaseUsageError.sdkNotConfigured
        }
        // After adding the SDK, replace with:
        //
        // guard let userId = client.auth.session?.user.id else {
        //     throw SupabaseUsageError.notAuthenticated
        // }
        //
        // struct ProfileUpdate: Encodable { let plan: String }
        //
        // try await client
        //     .from("profiles")
        //     .update(ProfileUpdate(plan: plan))
        //     .eq("id", userId)
        //     .execute()
    }
}

