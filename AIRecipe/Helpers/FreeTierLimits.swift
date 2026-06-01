import Foundation

/// Free-tier daily import cap (aligned with `RecipeImportProcessor` paywall threshold).
enum FreeTierLimits {
    static let dailyImportLimit = 2

    static func remainingToday(usedToday: Int) -> Int {
        max(0, dailyImportLimit - usedToday)
    }

    static func importsUsedToday(userId: String) async throws -> Int {
        _ = userId
        return try await SupabaseService.shared.fetchAIUsageCount()
    }
}
