import Foundation
import RevenueCat

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    /// Must match the entitlement identifier in RevenueCat (dashboard → Entitlements).
    static let entitlementId = "pro"

    @Published private(set) var isPremium: Bool = false

    private init() {}

    func checkStatus() async {
        do {
            // Ensure RevenueCat has the latest App Store receipt / CustomerInfo.
            _ = try await Purchases.shared.syncPurchases()
            let customerInfo = try await Purchases.shared.customerInfo()
            await applyCustomerInfoAndMirrorPlan(customerInfo)
        } catch {
            print("SubscriptionManager: failed to fetch customer info: \(error)")
        }
    }

    /// Call after Supabase sign-in so purchases and restores attach to this app user (required for Sandbox / production + RevenueCat).
    func syncRevenueCatWithAuthenticatedUser() async {
        guard let userId = await SupabaseService.shared.currentUserIdString() else { return }
        do {
            _ = try await Purchases.shared.logIn(userId)
            await checkStatus()
        } catch {
            print("SubscriptionManager: RevenueCat logIn failed: \(error)")
        }
    }

    /// Call after Supabase sign-out so the next user does not inherit the previous customer’s entitlements.
    func signOutRevenueCat() async {
        do {
            _ = try await Purchases.shared.logOut()
        } catch {
            print("SubscriptionManager: RevenueCat logOut failed: \(error)")
        }
        isPremium = false
        UserDefaults.standard.set("Free", forKey: "settings.subscriptionTier")
    }

    /// Updates local premium flag and Supabase when RevenueCat pushes new `CustomerInfo` (e.g. after a real purchase completes).
    func applyCustomerInfoAndMirrorPlan(_ customerInfo: CustomerInfo) async {
        let active = customerInfo.entitlements[Self.entitlementId]?.isActive ?? false
        isPremium = active
        let planType = active ? "pro" : "free"
        let displayTier = active ? "Pro" : "Free"
        UserDefaults.standard.set(displayTier, forKey: "settings.subscriptionTier")
        do {
            if let userId = await SupabaseService.shared.currentUserIdString() {
                try await RecipeBackendService.shared.syncSubscriptionPlan(planType: planType, userId: userId)
            }
        } catch {
            print("SubscriptionManager: failed to sync plan via backend: \(error)")
        }
    }

    /// Refresh RevenueCat entitlement and mirror it to Supabase `profiles.plan_type`.
    func refreshAndSyncPlan() async {
        await checkStatus()
    }
}

// MARK: - PurchasesDelegate

/// Retain one instance on `Purchases.shared.delegate` so entitlement changes from the App Store update UI immediately.
final class RevenueCatPurchasesDelegate: NSObject, PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            await SubscriptionManager.shared.applyCustomerInfoAndMirrorPlan(customerInfo)
        }
    }
}
