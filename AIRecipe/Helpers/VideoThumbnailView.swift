import SwiftUI
import AVKit
import WebKit

/// Recipe video preview: plays downloaded video URL, or YouTube embed, or shows thumbnail/placeholder.
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
                YouTubeEmbedView(url: embedURL)
            } else if let data = customImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if source == .youtube, let url = Recipe.youtubeThumbnailURL(from: sourceURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        placeholderView
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(height: 200)
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

struct YouTubeEmbedView: View {
    let url: URL

    var body: some View {
        WebView(url: url)
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
