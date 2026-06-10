import Foundation

/// Free-tier import cap — mirrors Supabase `profiles.ai_usage_count` / backend `use_ai_once`.
enum FreeTierLimits {
    static let dailyImportLimit = 3

    static func remainingToday(usedToday: Int) -> Int {
        max(0, dailyImportLimit - usedToday)
    }

    static func isImportLimitReached(usedCount: Int) -> Bool {
        usedCount >= dailyImportLimit
    }

    static func importsUsedToday(userId: String) async throws -> Int {
        _ = userId
        return try await SupabaseService.shared.fetchAIUsageCount()
    }
}
