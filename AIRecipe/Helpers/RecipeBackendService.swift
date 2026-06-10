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
    let timestamp_seconds: String?

    init(step: Int, description: String, timestamp_seconds: String? = nil) {
        self.step = step
        self.description = description
        self.timestamp_seconds = timestamp_seconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        step = try container.decode(Int.self, forKey: .step)
        description = try container.decode(String.self, forKey: .description)
        timestamp_seconds = Self.decodeFlexibleTimestamp(from: container)
    }

    private enum CodingKeys: String, CodingKey {
        case step, description, timestamp_seconds
    }

    /// AI may return `"12.5"` or `12.5`; accept both so import jobs don't fail to decode.
    private static func decodeFlexibleTimestamp(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> String? {
        if let text = try? container.decode(String.self, forKey: .timestamp_seconds) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = try? container.decode(Double.self, forKey: .timestamp_seconds) {
            return String(value)
        }
        if let value = try? container.decode(Int.self, forKey: .timestamp_seconds) {
            return String(value)
        }
        return nil
    }
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
    let thumbnail_url: String?
    let dish_hero_timestamp_seconds: String?
}

struct ImportEnqueueResponse: Codable {
    let job_id: String
    let status: String
}

struct RemoteImportJob: Codable {
    let id: String
    let url: String
    let user_id: String
    let source_type: String
    let status: String
    let created_at: String?
    let updated_at: String?
    let error_log: String?
    let result_json: [String: JSONValue]?
}

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - Backend config

enum RecipeBackendConfig {
    static var baseURL: String {
        #if targetEnvironment(simulator)
            return "http://127.0.0.1:8000"
        #else
           // return "https://ai-recipe-app-1-h59j.onrender.com"
            return "http://10.0.0.94:8000"
        #endif
    }

    /// Absolute URL for an API path (e.g. `"analyze_reel"` or `"analyze_video_upload"`). Avoids `URL(relativeTo:)` edge cases with some base strings.
    static func endpointURL(path: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.last == "/" { base.removeLast() }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        guard !tail.isEmpty else { return URL(string: base) }
        return URL(string: base + "/" + tail)
    }

    /// Resolves thumbnail/media URLs from the API. Rewrites loopback hosts when the app uses a different API base (common for queued imports).
    static func resolvedMediaURL(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("file://"), let u = URL(string: s) { return u }
        if s.hasPrefix("/") { return URL(fileURLWithPath: s) }

        guard var thumb = URLComponents(string: s),
              let api = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let apiHost = api.host
        else {
            return URL(string: s)
        }

        let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "0.0.0.0"]
        let thumbHost = (thumb.host ?? "").lowercased()
        if loopbackHosts.contains(thumbHost), thumbHost != apiHost.lowercased() {
            thumb.scheme = api.scheme ?? thumb.scheme
            thumb.host = apiHost
            thumb.port = api.port
        }
        return thumb.url ?? URL(string: s)
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

    /// Default `URLSession` idles out (~60s) while the backend downloads video + runs Gemini with no response bytes. Use this for analyze calls only.
    /// Note: Some hosts (e.g. free-tier proxies) still enforce their own max request duration.
    private static let longRunningAnalyzeSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900
        config.timeoutIntervalForResource = 1800
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private init() {}

    /// Sends the video URL (and language) to the backend and returns the analyzed recipe response.
    /// Pass `userId` (Supabase auth user UUID string) when your API enforces quota via `X-User-Id` + Supabase RPC.
    func analyzeReel(url: String, language: String, userId: String? = nil, isPro: Bool? = nil) async throws -> RecipeAnalyzeResponse {
        guard let endpoint = RecipeBackendConfig.endpointURL(path: "analyze_reel") else {
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
            (data, response) = try await Self.longRunningAnalyzeSession.data(for: request)
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

    /// Queue a link import server-side and return backend job id.
    func enqueueImport(url: String, language: String, userId: String) async throws -> ImportEnqueueResponse {
        guard let endpoint = RecipeBackendConfig.endpointURL(path: "import") else {
            throw RecipeBackendError.invalidURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userId, forHTTPHeaderField: "X-User-Id")
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
        return try JSONDecoder().decode(ImportEnqueueResponse.self, from: data)
    }

    /// Poll import jobs for current user.
    func fetchImportJobs(userId: String, status: String? = nil, limit: Int = 50) async throws -> [RemoteImportJob] {
        guard var endpoint = RecipeBackendConfig.endpointURL(path: "import/jobs") else {
            throw RecipeBackendError.invalidURL
        }
        if var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) {
            var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
            if let status, !status.isEmpty {
                items.append(URLQueryItem(name: "status", value: status))
            }
            components.queryItems = items
            if let u = components.url { endpoint = u }
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(userId, forHTTPHeaderField: "X-User-Id")
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
        return try JSONDecoder().decode([RemoteImportJob].self, from: data)
    }

    /// Uploads a local video file (e.g. from Photos) for the same Gemini pipeline as TikTok/Instagram downloads.
    func analyzeUploadedVideo(fileURL: URL, language: String, userId: String?, isPro: Bool? = nil) async throws -> RecipeAnalyzeResponse {
        guard let endpoint = RecipeBackendConfig.endpointURL(path: "analyze_video_upload") else {
            throw RecipeBackendError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let userId, !userId.isEmpty {
            request.setValue(userId, forHTTPHeaderField: "X-User-Id")
        }
        if let isPro {
            request.setValue(isPro ? "true" : "false", forHTTPHeaderField: "X-Is-Pro")
        }

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent.isEmpty ? "video.mp4" : fileURL.lastPathComponent
        let ext = (filename as NSString).pathExtension.lowercased()
        let mimeType: String
        switch ext {
        case "mov": mimeType = "video/quicktime"
        case "m4v": mimeType = "video/x-m4v"
        default: mimeType = "video/mp4"
        }
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"language\"\r\n\r\n\(language)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.longRunningAnalyzeSession.data(for: request)
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

        return try JSONDecoder().decode(RecipeAnalyzeResponse.self, from: data)
    }

    /// Server calls Supabase `use_export_once` with the service role (client only sends `X-User-Id`).
    func recordExportUsage(userId: String) async throws {
        try await postJSON(path: "usage/export_once", userId: userId, body: EmptyEncodable())
    }

    private struct EmptyEncodable: Encodable {}

    private struct PlanUpdateBody: Encodable {
        let plan_type: String
    }

    /// Server PATCHes `profiles.plan_type` (RevenueCat mirror).
    func syncSubscriptionPlan(planType: String, userId: String) async throws {
        try await postJSON(path: "profile/plan", userId: userId, body: PlanUpdateBody(plan_type: planType))
    }

    private func postJSON<Body: Encodable>(path: String, userId: String, body: Body) async throws {
        guard let endpoint = RecipeBackendConfig.endpointURL(path: path) else {
            throw RecipeBackendError.invalidURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userId, forHTTPHeaderField: "X-User-Id")
        request.httpBody = try JSONEncoder().encode(body)

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
    }
}

// MARK: - Map API response → Recipe (for SwiftData)

extension RecipeAnalyzeResponse {
    /// Persists a loadable thumbnail URL (rewrites loopback hosts to match the app’s API base).
    static func storedMediaURLString(thumbnail_url: String?, video_url: String?) -> String {
        let raw = (thumbnail_url ?? video_url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        return RecipeBackendConfig.resolvedMediaURL(raw)?.absoluteString ?? raw
    }

    static func storedThumbnailURLString(thumbnail_url: String?) -> String {
        let raw = (thumbnail_url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        return RecipeBackendConfig.resolvedMediaURL(raw)?.absoluteString ?? raw
    }

    static func storedVideoPlaybackURLString(video_url: String?) -> String {
        let raw = (video_url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        return RecipeBackendConfig.resolvedMediaURL(raw)?.absoluteString ?? raw
    }

    static func joinedStepTimestamps(from instructions: [RecipeInstructionItem]) -> String {
        instructions
            .sorted { $0.step < $1.step }
            .map { String(parseHeroSeconds(from: $0.timestamp_seconds)) }
            .joined(separator: ",")
    }

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
        let heroSeconds = Self.parseHeroSeconds(from: dish_hero_timestamp_seconds)

        let ownerId = SupabaseService.shared.client.auth.currentSession?.user.id.uuidString ?? ""
        let recipe = Recipe(
            ownerUserId: ownerId,
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
            downloadedVideoURL: Self.storedThumbnailURLString(thumbnail_url: thumbnail_url),
            videoPlaybackURL: Self.storedVideoPlaybackURLString(video_url: video_url),
            stepTimestampsContent: Self.joinedStepTimestamps(from: instructions),
            dishHeroTimestampSeconds: heroSeconds
        )
        modelContext.insert(recipe)
        return recipe
    }

    /// Copies analyzed fields into a `RecipeImportSubmission` for the Imports queue (approve → `Recipe`).
    func applyToPendingImport(_ submission: RecipeImportSubmission, finalSourceURL: String) {
        let title = recipe_name.trimmingCharacters(in: .whitespacesAndNewlines)
        submission.readyTitle = title.isEmpty ? "Imported recipe" : title
        submission.readyCreator = creator.trimmingCharacters(in: .whitespacesAndNewlines)
        submission.readyNotes = description.trimmingCharacters(in: .whitespacesAndNewlines)
        submission.readyIngredients = ingredients.map { "\($0.item) - \($0.amount)" }.joined(separator: "\n")
        submission.readySteps = instructions.sorted(by: { $0.step < $1.step }).map(\.description).joined(separator: "\n")
        submission.readyPrepMinutes = Self.parseMinutes(from: prep_time ?? "")
        submission.readyCookMinutes = Self.parseMinutes(from: estimated_cooking_time)
        submission.readyTotalSteps = instructions.count
        submission.readySource = RecipeSource.inferred(from: finalSourceURL).rawValue
        submission.readySourceURL = finalSourceURL
        submission.readyDownloadedVideoURL = Self.storedThumbnailURLString(thumbnail_url: thumbnail_url)
        submission.readyVideoPlaybackURL = Self.storedVideoPlaybackURLString(video_url: video_url)
        submission.readyStepTimestamps = Self.joinedStepTimestamps(from: instructions)
        submission.readyDishHeroSeconds = Self.parseHeroSeconds(from: dish_hero_timestamp_seconds)
    }

    static func parseHeroSeconds(from raw: String?) -> Double {
        guard let raw, !raw.isEmpty else { return 0 }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if let v = Double(s), v >= 0, v.isFinite { return v }
        if let r = s.range(of: #"[\d.]+"#, options: .regularExpression), let v = Double(s[r]), v >= 0, v.isFinite {
            return v
        }
        return 0
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

extension RemoteImportJob {
    var parsedAnalyzeResponse: RecipeAnalyzeResponse? {
        guard let result_json else { return nil }
        guard let data = try? JSONEncoder().encode(result_json) else { return nil }
        return try? JSONDecoder().decode(RecipeAnalyzeResponse.self, from: data)
    }

    /// Fallback when `instructions[].timestamp_seconds` was numeric in stored JSON.
    var stepTimestampsFromRawJSON: String? {
        guard let result_json,
              let instructions = result_json["instructions"],
              case .array(let items) = instructions else { return nil }
        let values: [String] = items.compactMap { item in
            guard case .object(let dict) = item else { return nil }
            switch dict["timestamp_seconds"] {
            case .string(let s):
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : String(RecipeAnalyzeResponse.parseHeroSeconds(from: t))
            case .number(let n):
                return String(max(0, n))
            default:
                return nil
            }
        }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: ",")
    }

    var videoURLFromRawJSON: String? {
        guard let result_json, case .string(let raw) = result_json["video_url"] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
