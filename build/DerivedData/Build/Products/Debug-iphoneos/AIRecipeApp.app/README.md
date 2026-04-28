# Subscriptions

- **Paywall:** Settings → **Upgrade to Premium** opens **RevenueCat**’s `PaywallView` (from RevenueCatUI). Configure offerings and paywalls in the RevenueCat dashboard.
- **Real App Store testing:** The main app scheme does **not** attach `Products.storekit`, so purchases come from **App Store Connect** (use a **Sandbox Apple ID** on device or **TestFlight**). Product IDs in App Store Connect must match RevenueCat and the optional local file `Products.storekit` (kept only if you manually attach it in Xcode for simulator-only experiments).
- **RevenueCat ↔ Supabase:** After sign-in, the app calls `Purchases.logIn` with your Supabase user id so receipts and entitlements attach to the right user. Sign-out calls `Purchases.logOut`.
- **Entitlement id:** Code expects entitlement identifier **`pro`** in RevenueCat (see `SubscriptionManager.entitlementId`).
