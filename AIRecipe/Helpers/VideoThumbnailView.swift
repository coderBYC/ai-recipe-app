import SwiftUI
import WebKit

/// Recipe media:
/// - YouTube: embed player
/// - Instagram/TikTok/Photos: backend-generated thumbnail image URL
struct VideoThumbnailView: View {
    let sourceURL: String
    let downloadedVideoURL: String
    let source: RecipeSource
    let dishHeroTimestampSeconds: Double

    init(
        sourceURL: String,
        downloadedVideoURL: String = "",
        source: RecipeSource,
        dishHeroTimestampSeconds: Double = 0
    ) {
        self.sourceURL = sourceURL
        self.downloadedVideoURL = downloadedVideoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.dishHeroTimestampSeconds = dishHeroTimestampSeconds
    }

    var body: some View {
        Group {
            switch source {
            case .youtube:
                if let embedURL = Recipe.youtubeEmbedURL(from: sourceURL) {
                    YouTubeEmbedView(embedURL: embedURL)
                } else {
                    placeholderView
                }
            case .instagram, .tiktok, .photos:
                thumbnailImageView
            }
        }
        .frame(height: 280)
        .clipped()
    }

    private var playableDownloadedURL: URL? {
        let s = downloadedVideoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("file://"), let u = URL(string: s) { return u }
        if s.hasPrefix("/") { return URL(fileURLWithPath: s) }
        return URL(string: s)
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(AppTheme.primary.opacity(0.15))
            .overlay {
                Image(systemName: source.iconName)
                    .font(AppTheme.bitterFont(size: 48, weight: .regular))
                    .foregroundStyle(AppTheme.primary.opacity(0.5))
            }
    }

    private var thumbnailImageView: some View {
        Group {
            if let url = playableDownloadedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholderView
                    case .empty:
                        ZStack {
                            placeholderView
                            ProgressView()
                        }
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
    }
}

// MARK: - Recipe list row thumbnail (right side)

struct RecipeListThumbnailView: View {
    let recipe: Recipe
    /// Square list thumbnail; fits beside title in `RecipeRowView`.
    private let side: CGFloat = 72

    var body: some View {
        Group {
            if recipe.sourceEnum == .youtube, let thumb = Recipe.youtubeThumbnailURL(from: recipe.sourceURL) {
                AsyncImage(url: thumb) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            placeholder
                            ProgressView()
                                .scaleEffect(0.85)
                        }
                    @unknown default:
                        placeholder
                    }
                }
            } else if let url = Self.playableDownloadedURL(recipe) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            placeholder
                            ProgressView()
                                .scaleEffect(0.85)
                        }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius)
                .stroke(AppTheme.textSecondary.opacity(0.28), lineWidth: AppTheme.boxBorderWidth)
        )
    }

    private var placeholder: some View {
        Rectangle()
            .fill(AppTheme.primary.opacity(0.12))
            .overlay {
                SourceIconView(source: recipe.sourceEnum)
            }
    }

    private static func playableDownloadedURL(_ recipe: Recipe) -> URL? {
        let s = recipe.downloadedVideoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("file://"), let u = URL(string: s) { return u }
        if s.hasPrefix("/") { return URL(fileURLWithPath: s) }
        return URL(string: s)
    }
}

// MARK: - YouTube embed (WKWebView)

struct YouTubeEmbedView: View {
    let embedURL: URL

    var body: some View {
        YouTubeWebView(embedURL: embedURL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

private struct YouTubeWebView: UIViewRepresentable {
    let embedURL: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptEnabled = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        let bundleId = Bundle.main.bundleIdentifier ?? "com.example.app"
        let referrer = "https://\(bundleId)".lowercased()
        guard let baseURL = URL(string: referrer) else {
            webView.load(URLRequest(url: embedURL))
            return webView
        }
        let html = """
        <!DOCTYPE html>
        <html style="height:100%;margin:0;padding:0;">
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        </head>
        <body style="height:100%;margin:0;padding:0;background:#000;">
            <iframe style="position:absolute;left:0;top:0;width:100%;height:100%;border:0;" src="\(embedURL.absoluteString)" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen playsinline></iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
