import Foundation

/// Public JSON from a GitHub Gist raw URL, updated by `RecipeBackend/cloudflare_gist_relay.py`.
private struct GistBackendConfig: Decodable {
    let url: String
}

/// Fetches the live Cloudflare tunnel base URL from a gist (Instagram-only path in `RecipeBackendService`).
final class BackendConfigDiscovery {
    static let shared = BackendConfigDiscovery()
    /// Safe fallback so Instagram relay works even if xcconfig key is missing.
    private let defaultGistRawURL = "https://gist.githubusercontent.com/coderBYC/3207f8bef4c8f9248d79563696042c53/raw/backend_config.json"

    private let lock = NSLock()
    private var cachedRelayBaseURL: String?

    private init() {}

    /// Last successfully fetched relay URL (normalized: no trailing slash), or nil.
    func currentRelayBaseURL() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cachedRelayBaseURL
    }

    /// Loads `BACKEND_CONFIG_GIST_RAW_URL` from Info.plist / DEBUG env; falls back to default gist; fetches JSON with 2s retries.
    func refreshFromGistIfConfigured() async {
        let configured = AppSecrets.backendConfigGistRawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawGist = configured.isEmpty ? defaultGistRawURL : configured
        guard let url = URL(string: rawGist) else { return }

        for attempt in 1...4 {
            do {
                var request = URLRequest(url: url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue(
                    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                    forHTTPHeaderField: "User-Agent"
                )
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let decoded = try JSONDecoder().decode(GistBackendConfig.self, from: data)
                let trimmed = decoded.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, URL(string: trimmed) != nil else { throw URLError(.cannotParseResponse) }
                let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
                lock.lock()
                cachedRelayBaseURL = normalized
                lock.unlock()
                return
            } catch {
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }
}
