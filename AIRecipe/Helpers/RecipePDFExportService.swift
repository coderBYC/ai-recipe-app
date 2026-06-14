import Foundation
import SwiftUI
import UIKit
import WebKit

enum RecipePDFExportError: LocalizedError {
    case pdfGenerationFailed
    case invalidImageURL

    var errorDescription: String? {
        switch self {
        case .pdfGenerationFailed: return "Could not create the recipe PDF."
        case .invalidImageURL: return "Could not load recipe images for export."
        }
    }
}

enum RecipePDFExportService {
    private static let renderQueue = DispatchQueue(label: "com.airecipe.recipePDFExport", qos: .userInitiated)

    static func generatePDF(from recipe: Recipe, servings: Int) async throws -> Data {
        let html = RecipePDFHTMLBuilder.buildHTML(from: recipe, servings: servings)
        return try await generatePDF(html: html)
    }

    static func generatePDF(html: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            renderQueue.async {
                Task { @MainActor in
                    do {
                        let data = try await RecipePDFWebViewRenderer.shared.render(html: html)
                        continuation.resume(returning: data)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

// MARK: - HTML

enum RecipePDFHTMLBuilder {
    static func buildHTML(from recipe: Recipe, servings: Int) -> String {
        let title = escapeHTML(recipe.title.isEmpty ? "Recipe" : recipe.title)
        let servingsText = escapeHTML("\(max(1, servings))")
        let prepTime = escapeHTML(formatMinutes(recipe.prepMinutes))
        let cookTime = escapeHTML(formatMinutes(recipe.estimatedCookingMinutes))
        let tips = escapeHTML(recipe.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No tips added yet."
            : recipe.notes.trimmingCharacters(in: .whitespacesAndNewlines))
        let ingredientsHTML = ingredientsListHTML(recipe: recipe, servings: servings)
        let stepsHTML = stepsListHTML(recipe: recipe)
        let thumbnailURL = escapeHTML(thumbnailURLString(for: recipe))
        let appIconURL = escapeHTML(appIconSourceURL())

        let thumbnailBlock: String
        if thumbnailURL.isEmpty {
            thumbnailBlock = ""
        } else {
            thumbnailBlock = """
                <div class="thumbnail-container">
                    <img class="recipe-thumbnail" src="\(thumbnailURL)" alt="Recipe Preview">
                </div>
            """
        }

        return template
            .replacingOccurrences(of: "{{APP_ICON_URL}}", with: appIconURL)
            .replacingOccurrences(of: "{{RECIPE_TITLE}}", with: title)
            .replacingOccurrences(of: "{{SERVINGS}}", with: servingsText)
            .replacingOccurrences(of: "{{PREP_TIME}}", with: prepTime)
            .replacingOccurrences(of: "{{COOK_TIME}}", with: cookTime)
            .replacingOccurrences(of: "{{INGREDIENTS_LIST}}", with: ingredientsHTML)
            .replacingOccurrences(of: "{{DIRECTIONS_STEPS}}", with: stepsHTML)
            .replacingOccurrences(of: "{{TIPS_AND_VARIATIONS}}", with: tips)
            .replacingOccurrences(of: "{{THUMBNAIL_BLOCK}}", with: thumbnailBlock)
    }

    private static let template = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <style>
        @page {
            size: A4;
            margin: 15mm;
        }

        *, *::before, *::after {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            padding: 0;
            font-family: "Georgia", serif;
            color: #222222;
            font-size: 10.5pt;
            line-height: 1.55;
            background-color: #ffffff;
        }

        .brand-header {
            text-align: center;
            margin-bottom: 5px;
        }

        .chef-icon {
            width: 42px;
            height: 42px;
            object-fit: contain;
        }

        .recipe-title {
            font-size: 26pt;
            font-weight: normal;
            text-align: center;
            margin-top: 5px;
            margin-bottom: 15px;
            color: #111111;
        }

        .meta-container {
            display: table;
            width: 100%;
            border-top: 1px solid #111111;
            border-bottom: 1px solid #111111;
            padding: 10px 0;
            margin-bottom: 25px;
        }

        .meta-item {
            display: table-cell;
            width: 33.33%;
            text-align: center;
            vertical-align: middle;
            font-size: 9.5pt;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .meta-item strong {
            display: block;
            font-size: 10.5pt;
            margin-top: 3px;
        }

        .meta-divider {
            border-right: 1px solid #e1e1e1;
        }

        .main-layout {
            display: table;
            width: 100%;
            table-layout: fixed;
        }

        .layout-row {
            display: table-row;
        }

        .left-column {
            display: table-cell;
            width: 38%;
            padding-right: 25px;
            vertical-align: top;
        }

        .right-column {
            display: table-cell;
            width: 62%;
            padding-left: 25px;
            border-left: 1px solid #e1e1e1;
            vertical-align: top;
        }

        .section-title {
            font-size: 12pt;
            font-weight: bold;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-top: 0;
            margin-bottom: 14px;
            color: #111111;
        }

        .ingredients-box {
            background-color: #fcf8f2;
            padding: 20px;
            border-radius: 6px;
            margin-bottom: 25px;
            border: 1px solid #f2e9dc;
        }

        .ingredients-list {
            list-style-type: none;
            padding-left: 0;
            margin: 0;
        }

        .ingredients-list li {
            margin-bottom: 9px;
            font-size: 10.5pt;
            border-bottom: 1px dashed #e1e1e1;
            padding-bottom: 5px;
        }

        .tips-box {
            padding-top: 5px;
        }

        .tips-text {
            font-size: 10pt;
            color: #444444;
            font-style: italic;
            line-height: 1.6;
        }

        .directions-list {
            padding-left: 22px;
            margin: 0;
        }

        .directions-list li {
            margin-bottom: 14px;
            padding-left: 3px;
        }

        .thumbnail-container {
            margin-top: 35px;
            text-align: center;
            page-break-inside: avoid;
        }

        .recipe-thumbnail {
            width: 100%;
            max-height: 250px;
            object-fit: cover;
            border-radius: 8px;
        }
    </style>
    </head>
    <body>

        <div class="brand-header">
            <img class="chef-icon" src="{{APP_ICON_URL}}" alt="Let Him Cook">
        </div>

        <div class="recipe-title">{{RECIPE_TITLE}}</div>

        <div class="meta-container">
            <div class="meta-item meta-divider">
                Servings
                <strong>{{SERVINGS}}</strong>
            </div>
            <div class="meta-item meta-divider">
                Prep Time
                <strong>{{PREP_TIME}}</strong>
            </div>
            <div class="meta-item">
                Cook Time
                <strong>{{COOK_TIME}}</strong>
            </div>
        </div>

        <div class="main-layout">
            <div class="layout-row">
                <div class="left-column">
                    <div class="ingredients-box">
                        <div class="section-title">Ingredients</div>
                        <ul class="ingredients-list">
                            {{INGREDIENTS_LIST}}
                        </ul>
                    </div>

                    <div class="tips-box">
                        <div class="section-title">Tips and Variations</div>
                        <div class="tips-text">{{TIPS_AND_VARIATIONS}}</div>
                    </div>
                </div>

                <div class="right-column">
                    <div class="section-title">Directions</div>
                    <ol class="directions-list">
                        {{DIRECTIONS_STEPS}}
                    </ol>

                    {{THUMBNAIL_BLOCK}}
                </div>
            </div>
        </div>

    </body>
    </html>
    """

    private static func ingredientsListHTML(recipe: Recipe, servings: Int) -> String {
        let base = max(1, recipe.estimatedServings)
        let scale = Double(max(1, servings)) / Double(base)
        let lines = recipe.ingredientLines
        guard !lines.isEmpty else {
            return "<li>No ingredients listed</li>"
        }
        return lines.map { line in
            let parsed = IngredientLine.parse(line)
            let amount = IngredientAmountScaler.scaledAmount(parsed.amount, factor: scale)
            let text: String
            if amount.isEmpty {
                text = parsed.name
            } else if parsed.name.isEmpty {
                text = amount
            } else {
                text = "\(parsed.name) — \(amount)"
            }
            return "<li>\(escapeHTML(text))</li>"
        }.joined()
    }

    private static func stepsListHTML(recipe: Recipe) -> String {
        let steps = recipe.stepLines
        guard !steps.isEmpty else {
            return "<li>No steps listed</li>"
        }
        return steps.map { "<li>\(escapeHTML($0))</li>" }.joined()
    }

    private static func thumbnailURLString(for recipe: Recipe) -> String {
        if let cloud = recipe.premiumCloudinaryURLString,
           let url = SmartThumbnailCloudinary.resizedURL(from: cloud, width: 720, height: 420) {
            return url.absoluteString
        }
        if recipe.sourceEnum == .youtube,
           let url = Recipe.youtubeThumbnailURL(from: recipe.sourceURL) {
            return url.absoluteString
        }
        let stored = recipe.downloadedVideoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty, let resolved = RecipeBackendConfig.resolvedMediaURL(stored) {
            return resolved.absoluteString
        }
        return ""
    }

    /// Embedded app icon so PDF export works offline inside WKWebView.
    private static func appIconSourceURL() -> String {
        if let image = UIImage(named: "icon"),
           let data = image.pngData() {
            return "data:image/png;base64,\(data.base64EncodedString())"
        }
        if let image = UIImage(named: "AppIcon"),
           let data = image.pngData() {
            return "data:image/png;base64,\(data.base64EncodedString())"
        }
        return ""
    }

    private static func formatMinutes(_ minutes: Int) -> String {
        minutes > 0 ? "\(minutes) min" : "—"
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - WKWebView PDF renderer

@MainActor
private final class RecipePDFWebViewRenderer: NSObject, WKNavigationDelegate {
    static let shared = RecipePDFWebViewRenderer()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Data, Error>?

    func render(html: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 595.2, height: 841.8))
            webView.navigationDelegate = self
            self.webView = webView
            webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            let configuration = WKPDFConfiguration()
            webView.createPDF(configuration: configuration) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    defer {
                        self.webView = nil
                        self.continuation = nil
                    }
                    switch result {
                    case .success(let data) where !data.isEmpty:
                        self.continuation?.resume(returning: data)
                    case .success:
                        self.continuation?.resume(throwing: RecipePDFExportError.pdfGenerationFailed)
                    case .failure(let error):
                        self.continuation?.resume(throwing: error)
                    }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishWithError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishWithError(error)
    }

    private func finishWithError(_ error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        webView = nil
    }
}

// MARK: - Filename helper

extension String {
    fileprivate var sanitizedPDFFilename: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Recipe" : trimmed
    }
}

extension Recipe {
    func temporaryPDFExportURL(data: Data) throws -> URL {
        let name = (title.isEmpty ? "Recipe" : title).sanitizedPDFFilename
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - HTML preview + share

struct RecipePDFHTMLWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var loadedHTML: String?
    }
}

struct RecipePDFPreviewSheet: View {
    let html: String
    let pdfURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            RecipePDFHTMLWebView(html: html)
                .background(Color.white)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("PDF Preview")
                            .nanumAppFont(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(AppTheme.primary)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(AppTheme.bitterFont(size: 18, weight: .regular))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .accessibilityLabel("Share PDF")
                    }
                }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [pdfURL])
        }
    }
}
