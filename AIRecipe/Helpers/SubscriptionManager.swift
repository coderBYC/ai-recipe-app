import Foundation
import RevenueCat

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    static let entitlementId = "pro"

    @Published private(set) var isPremium: Bool = false

    private init() {}

    func checkStatus() async {
        do {
            // Ensure RevenueCat has the latest receipt state before reading entitlements.
            try await Purchases.shared.syncPurchases()
            let customerInfo = try await Purchases.shared.customerInfo()
            let active = customerInfo.entitlements[Self.entitlementId]?.isActive ?? false
            self.isPremium = active
        } catch {
            print("SubscriptionManager: failed to fetch customer info: \(error)")
        }
    }

    /// Refresh RevenueCat entitlement and mirror it to Supabase `profiles.plan_type`.
    func refreshAndSyncPlan() async {
        await checkStatus()
        let plan = isPremium ? "Pro" : "Free"
        UserDefaults.standard.set(plan, forKey: "settings.subscriptionTier")
        do {
            try await SupabaseService.shared.updatePlan(to: plan)
        } catch {
            print("SubscriptionManager: failed to sync plan to Supabase: \(error)")
        }
    }
}
