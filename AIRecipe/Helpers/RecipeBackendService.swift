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
        return "http://127.0.0.1:8000" // Use your Mac's IP when testing on a real device
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
    func analyzeReel(url: String, language: String) async throws -> RecipeAnalyzeResponse {
        guard let base = URL(string: RecipeBackendConfig.baseURL),
              let endpoint = URL(string: "/analyze_reel", relativeTo: base) else {
            throw RecipeBackendError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AnalyzeReelRequest(url: url, language: language))

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
        let estimatedCookingMinutes = Int(estimated_cooking_time.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let totalSteps = instructions.count

        let recipe = Recipe(
            title: title.isEmpty ? "Imported recipe" : title,
            source: source,
            sourceURL: sourceURL,
            creator: creator,
            timestamp: "",
            ingredients: ingredientsText,
            estimatedCookingMinutes: estimatedCookingMinutes,
            totalSteps: totalSteps,
            triedBefore: false,
            notes: notes,
            stepsContent: stepsText,
            downloadedVideoURL: video_url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
        modelContext.insert(recipe)
        return recipe
    }
}
