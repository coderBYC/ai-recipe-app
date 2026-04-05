import Foundation

/// Values are injected at build time via `Config/AppSecrets.xcconfig` → Info.plist.
/// Put real keys only in `Config/AppSecrets.local.xcconfig` (gitignored).
enum AppSecrets {
    private static func plistString(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var supabaseURL: URL? {
        let raw = plistString("SUPABASE_URL")
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    static var supabaseAnonKey: String {
        plistString("SUPABASE_ANON_KEY")
    }

    static var revenueCatPublicKey: String {
        plistString("REVENUECAT_API_KEY")
    }

    static let configurationHint = """
        Missing API keys. Copy Config/AppSecrets.local.xcconfig.example to \
        Config/AppSecrets.local.xcconfig, add SUPABASE_URL, SUPABASE_ANON_KEY, and REVENUECAT_API_KEY, \
        then clean build. Rotate any keys that were ever committed to git.
        """
}
