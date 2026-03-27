import SwiftUI
import AVKit
import WebKit

/// Recipe video preview: plays downloaded video URL, YouTube embed, or shows thumbnail/placeholder.
struct VideoThumbnailView: View {
    let sourceURL: String
    let customImageData: Data?
    let downloadedVideoURL: String
    let source: RecipeSource

    init(sourceURL: String, customImageData: Data?, downloadedVideoURL: String = "", source: RecipeSource) {
        self.sourceURL = sourceURL
        self.customImageData = customImageData
        self.downloadedVideoURL = downloadedVideoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
    }

    var body: some View {
        Group {
            if let url = playableDownloadedURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .onDisappear { /* optional: pause when off-screen */ }
            } else if source == .youtube, let embedURL = Recipe.youtubeEmbedURL(from: sourceURL) {
                YouTubeEmbedView(embedURL: embedURL)
            } else if let data = customImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }
        }
        .frame(height: 230)
        .clipped()
    }

    private var playableDownloadedURL: URL? {
        guard !downloadedVideoURL.isEmpty, let url = URL(string: downloadedVideoURL) else { return nil }
        return url
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(AppTheme.primary.opacity(0.15))
            .overlay {
                Image(systemName: source.iconName)
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.primary.opacity(0.5))
            }
    }
}

// MARK: - YouTube embed (WKWebView)
// 使用 loadHTMLString + baseURL 避免錯誤 153（YouTube 要求正確的 Referer）

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
        // html/body/iframe 100% height so no extra black block below; object-fit contain keeps aspect ratio inside frame
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
