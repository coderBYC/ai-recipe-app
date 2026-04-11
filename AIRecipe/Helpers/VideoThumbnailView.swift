import SwiftUI
import AVKit
import WebKit

/// Recipe video preview: plays downloaded video URL, YouTube embed, or shows thumbnail/placeholder.
struct VideoThumbnailView: View {
    let sourceURL: String
    let downloadedVideoURL: String
    let source: RecipeSource
    @State private var resolvedDownloadedURL: URL?

    init(sourceURL: String, downloadedVideoURL: String = "", source: RecipeSource) {
        self.sourceURL = sourceURL
        self.downloadedVideoURL = downloadedVideoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
    }

    var body: some View {
        Group {
            if let url = playableDownloadedURL {
                ResolvedVideoPlayer(url: url)
            } else if source == .youtube, let embedURL = Recipe.youtubeEmbedURL(from: sourceURL) {
                YouTubeEmbedView(embedURL: embedURL)
            } else {
                placeholderView
            }
        }
        .task(id: downloadedVideoURL) {
            await refreshResolvedVideoURLIfNeeded()
        }
        .frame(height: 230)
        .clipped()
    }

    private var playableDownloadedURL: URL? {
        if let resolvedDownloadedURL { return resolvedDownloadedURL }
        guard !downloadedVideoURL.isEmpty, let url = URL(string: downloadedVideoURL) else { return nil }
        return url
    }

    /// For Instagram/TikTok premium previews, rewrite stale `/video/{id}` links to the latest relay host.
    @MainActor
    private func refreshResolvedVideoURLIfNeeded() async {
        guard !downloadedVideoURL.isEmpty, let original = URL(string: downloadedVideoURL) else {
            resolvedDownloadedURL = nil
            return
        }
        guard source == .instagram || source == .tiktok else {
            resolvedDownloadedURL = original
            return
        }
        // Only rewrite backend-served paths; leave arbitrary absolute URLs untouched.
        guard original.path.hasPrefix("/video/") else {
            resolvedDownloadedURL = original
            return
        }

        await BackendConfigDiscovery.shared.refreshFromGistIfConfigured()
        guard let relay = BackendConfigDiscovery.shared.currentRelayBaseURL(),
              let relayBase = URL(string: relay) else {
            resolvedDownloadedURL = original
            return
        }

        var components = URLComponents()
        components.scheme = relayBase.scheme
        components.host = relayBase.host
        components.port = relayBase.port
        components.path = original.path
        components.query = original.query
        components.fragment = original.fragment
        resolvedDownloadedURL = components.url ?? original
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

private struct ResolvedVideoPlayer: View {
    let url: URL
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .task(id: url) {
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                // Start immediately; user still has native controls to pause/seek.
                player.play()
            }
            .onDisappear {
                player.pause()
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
