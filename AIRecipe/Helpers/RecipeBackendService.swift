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
    /// Base URL for the recipe analysis API. Use your machine's IP (e.g. http://192.168.1.x:8000) when testing on device.
    static var baseURL: String {
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:8000"
        #else
        return "http://35.3.118.45:8000" // Use your Mac's IP when testing on a real device
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

    /// Sends the video URL (and language) to the backend and returns the analyzed recipe response.
    /// Pass `userId` (Supabase auth user UUID string) when your API enforces quota via `X-User-Id` + Supabase RPC.
    func analyzeReel(url: String, language: String, userId: String? = nil) async throws -> RecipeAnalyzeResponse {
        guard let base = URL(string: RecipeBackendConfig.baseURL),
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
