# Subscriptions

- **Paywall:** Settings → **Upgrade to Premium** opens **RevenueCat**’s `PaywallView` (from RevenueCatUI). Configure offerings and paywalls in the RevenueCat dashboard.
- **StoreKit configuration:** The **AIRecipeApp** scheme still attaches **`Products.storekit`** for **Run** / **Test** so Simulator can resolve `com.airecipe.monthly` / `com.airecipe.yearly` while you develop. RevenueCat must use the **same product IDs** in its dashboard.

**Debug → StoreKit → Manage Transactions…** (Simulator) helps reset subscription state during testing.
