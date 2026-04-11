import Foundation
import SwiftData

// MARK: - Request / Response DTOs (match RecipeBackend main.py)

struct AnalyzeReelRequest: Encodable {
    let url: String
    let language: String
}

struct RecipeIngredientItem: Codable {
    let item: String
    let amount: String
}

struct RecipeInstructionItem: Codable {
    let step: Int
    let description: String
}

struct RecipeAnalyzeResponse: Codable {
    let recipe_name: String
    let description: String
    let creator: String
    let estimated_cooking_time: String
    let prep_time: String?
    let ingredients: [RecipeIngredientItem]
    let instructions: [RecipeInstructionItem]
    let video_url: String?
}

// MARK: - Backend config

enum RecipeBackendConfig {
    /// Default base URL (YouTube, TikTok, or fallback). **Instagram** may override via `BackendConfigDiscovery` (gist + Cloudflare tunnel).
    static var baseURL: String {
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:8000"
        #else
        return "https://ai-recipe-app-1-h59j.onrender.com"
        #endif
    }
}

// MARK: - Service

enum RecipeBackendError: Error {
    case invalidURL
    case network(Error)
    case invalidResponse
    case serverError(String)
}

final class RecipeBackendService {
    static let shared = RecipeBackendService()

    private init() {}

    private static func isInstagramReelURL(_ raw: String) -> Bool {
        let u = raw.lowercased()
        return u.contains("instagram.com") || u.contains("instagr.am")
    }

    /// Base URL for `/analyze_reel` — Instagram uses the gist-published tunnel when configured.
    private static func analysisBaseURL(forReelURL reelURL: String) async -> String {
        guard isInstagramReelURL(reelURL) else { return RecipeBackendConfig.baseURL }
        await BackendConfigDiscovery.shared.refreshFromGistIfConfigured()
        if let relay = BackendConfigDiscovery.shared.currentRelayBaseURL() {
            if await isRelayReachable(relay) {
            #if DEBUG
                print("Instagram request routed to relay: \(relay)")
            #endif
                return relay
            } else {
#if DEBUG
                print("Instagram relay unreachable, fallback to default backend: \(relay)")
#endif
            }
        }
        return RecipeBackendConfig.baseURL
    }

    /// Probe relay health quickly to avoid failing Instagram requests on stale gist hostnames.
    private static func isRelayReachable(_ relayBase: String) async -> Bool {
        guard let base = URL(string: relayBase),
              let url = URL(string: "/healthz", relativeTo: base) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    /// Sends the video URL (and language) to the backend and returns the analyzed recipe response.
    /// Pass `userId` (Supabase auth user UUID string) when your API enforces quota via `X-User-Id` + Supabase RPC.
    func analyzeReel(url: String, language: String, userId: String? = nil, isPro: Bool? = nil) async throws -> RecipeAnalyzeResponse {
        let baseString = await Self.analysisBaseURL(forReelURL: url)
        guard let base = URL(string: baseString),
              let endpoint = URL(string: "/analyze_reel", relativeTo: base) else {
            throw RecipeBackendError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AnalyzeReelRequest(url: url, language: language))
        if let userId, !userId.isEmpty {
            request.setValue(userId, forHTTPHeaderField: "X-User-Id")
        }
        if let isPro {
            request.setValue(isPro ? "true" : "false", forHTTPHeaderField: "X-Is-Pro")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RecipeBackendError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RecipeBackendError.invalidResponse
        }

        if http.statusCode != 200 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RecipeBackendError.serverError("\(http.statusCode): \(message)")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(RecipeAnalyzeResponse.self, from: data)
    }
}

// MARK: - Map API response → Recipe (for SwiftData)

extension RecipeAnalyzeResponse {
    /// Creates a Recipe model from the analyzed response and the original video URL.
    func toRecipe(sourceURL: String, modelContext: ModelContext) -> Recipe {
        let source = RecipeSource.inferred(from: sourceURL)
        let title = recipe_name.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let ingredientsText = ingredients.map { "\($0.item) - \($0.amount)" }.joined(separator: "\n")
        let stepsText = instructions.sorted(by: { $0.step < $1.step }).map(\.description).joined(separator: "\n")
        let creator = creator.trimmingCharacters(in: .whitespacesAndNewlines)
        let estimatedCookingMinutes = Self.parseMinutes(from: estimated_cooking_time)
        let prepMinutes = Self.parseMinutes(from: prep_time ?? "")
        let totalSteps = instructions.count

        let recipe = Recipe(
            title: title.isEmpty ? "Imported recipe" : title,
            source: source,
            sourceURL: sourceURL,
            creator: creator,
            timestamp: "",
            ingredients: ingredientsText,
            estimatedCookingMinutes: estimatedCookingMinutes,
            prepMinutes: prepMinutes,
            totalSteps: totalSteps,
            triedBefore: false,
            notes: notes,
            stepsContent: stepsText,
            downloadedVideoURL: video_url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
        modelContext.insert(recipe)
        return recipe
    }

    private static func parseMinutes(from raw: String) -> Int {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return 0 }
        // Extract first integer from strings like "10", "10 min", "10 minutes"
        let digits = s.filter { $0.isNumber || $0 == " " }
        if let match = s.range(of: #"\d+"#, options: .regularExpression) {
            return Int(s[match]) ?? 0
        }
        return Int(digits.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}
