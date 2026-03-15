//
//  Paywall.swift
//  AIRecipeApp
//
//  Created by Bryan Chen on 2026/3/14.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    /// Called when the user has an active subscription (product ID → "Pro Monthly" / "Pro Yearly"); syncs to Supabase.
    var onPlanUpdated: ((String) -> Void)?

    let productIDs = ["com.airecipe.monthly", "com.airecipe.yearly"]

    var body: some View {
        SubscriptionStoreView(productIDs: productIDs) {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text("Upgrade to Premium")
                    .font(.largeTitle.bold())
                Text("Unlimited AI recipes, exports, nutrition facts, and more.")
                    .font(.body)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 40)
        }
        .subscriptionStoreControlStyle(.picker)
        .storeButton(.visible, for: .restorePurchases)
        .task {
            await syncPlanFromEntitlements()
            for await _ in Transaction.updates {
                await syncPlanFromEntitlements()
            }
        }
    }

    private func syncPlanFromEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            if let plan = planName(for: tx.productID) {
                await MainActor.run {
                    onPlanUpdated?(plan)
                }
                return
            }
        }
    }

    private func planName(for productID: String) -> String? {
        if productID == "com.airecipe.monthly" { return "Pro Monthly" }
        if productID == "com.airecipe.yearly" { return "Pro Yearly" }
        return nil
    }
}

#Preview {
    PaywallView()
}
