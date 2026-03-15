import Foundation
// TODO: Add the Supabase Swift package to your Xcode project and then uncomment the import below.
// import Supabase

/// Configuration for the Supabase client used for subscriptions and usage limits.
enum SupabaseConfig {
    static let url = URL(string: "https://bebnwgehuzvrkjoiszdi.supabase.co")!
    /// Publishable key – safe to ship in the client.
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

    // Replace `Any` with `SupabaseClient` once you add the SDK.
    private let client: Any?

    private init() {
        // When you add the Supabase Swift SDK, initialize the real client, e.g.:
        //
        // self.client = SupabaseClient(
        //     supabaseURL: SupabaseConfig.url,
        //     supabaseKey: SupabaseConfig.key
        // )
        //
        // For now keep it nil so the compiler is happy without the SDK.
        self.client = nil
    }

    /// Call the `use_ai_once` RPC in Supabase to check and increment AI usage.
    func useAIOnce() async throws {
        guard client != nil else {
            throw SupabaseUsageError.sdkNotConfigured
        }
        // After adding the SDK, replace with:
        //
        // struct EmptyParams: Encodable {}
        // try await client.rpc("use_ai_once", params: EmptyParams()).execute()
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

