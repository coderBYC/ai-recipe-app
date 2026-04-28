import Foundation

/// Values are injected at build time via `Config/AppSecrets.xcconfig` → Info.plist.
/// Put real keys only in `Config/AppSecrets.local.xcconfig` (gitignored).
enum AppSecrets {
    /// Info.plist (build-time `$(VAR)` substitution) first; in DEBUG, falls back to process environment
    /// so SwiftUI Previews work if you add the same keys under Scheme → Run → Arguments → Environment Variables.
    private static func resolvedString(for key: String) -> String {
        let plist = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !plist.isEmpty, !plist.contains("$(") {
            return plist
        }
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        #endif
        return plist
    }

    /// Supabase Swift uses `supabaseURL.host!` for the auth token key; host **must** be non-nil.
    static var supabaseURL: URL? {
        let raw = resolvedString(for: "SUPABASE_URL")
        guard !raw.isEmpty else { return nil }
        // Build settings not applied — still literal in Info.plist.
        if raw.contains("$(") {
            return nil
        }
        var s = normalizeSupabaseURLString(raw)
        if !s.lowercased().hasPrefix("http://"), !s.lowercased().hasPrefix("https://") {
            s = "https://\(s)"
        }
        guard let u = URL(string: s), let host = u.host, !host.isEmpty else { return nil }
        guard let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        // e.g. https://https/... when URL was mistyped — DNS fails with host "https".
        if host == "https" || host == "http" {
            return nil
        }
        return u
    }

    /// Trims, strips accidental quotes from xcconfig, and fixes `https://https://...` (yields `https://https/auth/...` and -1003).
    private static func normalizeSupabaseURLString(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 2, s.first == "\"", s.last == "\"" {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Collapse duplicated scheme (copy/paste: https://https://xxx.supabase.co)
        while s.lowercased().hasPrefix("https://https://") {
            s = String(s.dropFirst("https://".count))
        }
        while s.lowercased().hasPrefix("http://https://") {
            s = String(s.dropFirst("http://".count))
        }
        return s
    }

    static var supabaseAnonKey: String {
        resolvedString(for: "SUPABASE_ANON_KEY")
    }

    static var revenueCatPublicKey: String {
        resolvedString(for: "REVENUECAT_API_KEY")
    }

    static let configurationHint = """
        Missing or invalid API configuration. Fix all of the following, then Clean Build Folder and build again:
        • Copy Config/AppSecrets.local.xcconfig.example to Config/AppSecrets.local.xcconfig (gitignored).
        • In .xcconfig, never type https:// in a value (// starts a comment). Use: SLASH = / then SUPABASE_URL = https:$(SLASH)$(SLASH)YOUR_REF.supabase.co — see AppSecrets.local.xcconfig.example.
        • If you still see $(SUPABASE_URL) in the built app, the xcconfig is not applied — check the AIRecipeApp target’s base configuration points to Config/AppSecrets.xcconfig and Config/AppSecrets.local.xcconfig exists beside it.
        • SwiftUI Previews: add SUPABASE_URL, SUPABASE_ANON_KEY, REVENUECAT_API_KEY to the scheme’s Environment Variables (DEBUG only), or run the full app target.
        • Rotate any keys that were ever committed to git.
        """
}
