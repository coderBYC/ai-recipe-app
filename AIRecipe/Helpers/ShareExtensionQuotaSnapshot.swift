import Foundation

/// Publishes free-tier usage into the App Group for the share extension UI.
enum ShareExtensionQuotaSnapshot {
    private static let suiteName = PendingRecipeImport.appGroupSuiteName
    private static let usedTodayKey = "shareExtensionQuotaUsedToday"
    private static let dailyLimitKey = "shareExtensionQuotaDailyLimit"
    private static let isPremiumKey = "shareExtensionQuotaIsPremium"

    @MainActor
    static func refreshFromBackend() async {
        await SubscriptionManager.shared.checkStatus()
        if SubscriptionManager.shared.isPremium {
            publish(usedToday: 0, isPremium: true)
            return
        }
        guard let userId = await SupabaseService.shared.currentUserIdString() else {
            publish(usedToday: 0, isPremium: false)
            return
        }
        let used = (try? await FreeTierLimits.importsUsedToday(userId: userId)) ?? 0
        publish(usedToday: min(FreeTierLimits.dailyImportLimit, used), isPremium: false)
    }

    static func publish(usedToday: Int, isPremium: Bool) {
        guard let suite = UserDefaults(suiteName: suiteName) else { return }
        suite.set(usedToday, forKey: usedTodayKey)
        suite.set(FreeTierLimits.dailyImportLimit, forKey: dailyLimitKey)
        suite.set(isPremium, forKey: isPremiumKey)
    }
}
