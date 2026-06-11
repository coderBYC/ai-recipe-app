import SwiftUI
import Kingfisher
import UIKit

/// Cook Mode recipe-list thumbnail with premium/free sourcing and Kingfisher disk cache.
///
/// **Premium:** Cloudinary URL via `KFImage` (cached on disk after first download).
/// **Free:** Kingfisher cache by `thumbId`, else on-device `AVAssetImageGenerator` frame capture.
struct SmartThumbnailView: View {
    let asset: SmartThumbnailAsset
    let isUserPremium: Bool
    /// Cook Mode steps always frame-capture by timestamp; list rows may use Cloudinary for premium.
    var mode: SmartThumbnailMode = .listHero
    var side: CGFloat = 120
    var cornerRadius: CGFloat = 12

    @State private var freeTierImage: UIImage?
    @State private var isLoadingFreeTier = false
    @State private var hasFailed = false
    @State private var imageVisible = false

    var body: some View {
        ZStack {
            thumbnailContent
        }
        .frame(width: side, height: side)
        .background(placeholderBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: taskIdentity) {
            resetState()
            await loadThumbnailIfNeeded()
        }
    }

    // MARK: - Routing

    private var usesPremiumCloudinary: Bool {
        guard case .listHero = mode else { return false }
        return isUserPremium && asset.premiumCloudinaryUrl != nil
    }

    private var taskIdentity: String {
        "\(asset.thumbId)|\(asset.timestampSeconds)|\(isUserPremium)|\(asset.premiumCloudinaryUrl ?? "")|\(asset.videoUrlString)"
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if hasFailed {
            failureView
        } else if usesPremiumCloudinary, let url = premiumImageURL {
            premiumKFImage(url: url)
        } else if let freeTierImage {
            localImageView(freeTierImage)
        } else if isLoadingFreeTier {
            loadingView
        } else {
            loadingView
        }
    }

    // MARK: - Premium (Cloudinary + Kingfisher)

    private var premiumImageURL: URL? {
        guard let raw = asset.premiumCloudinaryUrl else { return nil }
        return SmartThumbnailCloudinary.resizedURL(from: raw)
    }

    private func premiumKFImage(url: URL) -> some View {
        KFImage(url)
            .cacheOriginalImage()
            .onSuccess { _ in
                withAnimation(.easeIn(duration: 0.2)) {
                    imageVisible = true
                }
            }
            .onFailure { _ in
                hasFailed = true
            }
            .placeholder {
                loadingView
            }
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .opacity(imageVisible ? 1 : 0)
            .animation(.easeIn(duration: 0.2), value: imageVisible)
    }

    // MARK: - Free tier (cache → AVAsset frame capture)

    @MainActor
    private func loadThumbnailIfNeeded() async {
        if usesPremiumCloudinary {
            // KFImage handles its own loading lifecycle.
            return
        }

        // 1) Disk/memory cache hit → instant display, zero CPU.
        if let cached = await SmartThumbnailCache.cachedImage(forKey: asset.thumbId) {
            freeTierImage = cached
            revealImage()
            return
        }

        // 2) List hero: fall back to Cloudinary dish image (free tier — matches recipe page).
        if case .listHero = mode, let cloudURL = listHeroCloudinaryFallbackURL {
            if let cached = await SmartThumbnailCache.cachedImage(forKey: asset.thumbId) {
                freeTierImage = cached
                revealImage()
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: cloudURL)
                if let image = UIImage(data: data) {
                    await SmartThumbnailCache.store(image, forKey: asset.thumbId)
                    freeTierImage = image
                    revealImage()
                    return
                }
            } catch {
                // try MP4 frame capture below
            }
        }

        // 3) Miss → background frame capture, then persist to Kingfisher disk.
        guard let videoURL = resolvedVideoURL else {
            hasFailed = true
            return
        }

        isLoadingFreeTier = true
        defer { isLoadingFreeTier = false }

        do {
            let image = try await SmartThumbnailFrameExtractor.captureFrame(
                videoURL: videoURL,
                seconds: asset.timestampSeconds
            )
            await SmartThumbnailCache.store(image, forKey: asset.thumbId)
            freeTierImage = image
            revealImage()
        } catch {
            hasFailed = true
        }
    }

    private var resolvedVideoURL: URL? {
        let raw = asset.videoUrlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return RecipeBackendConfig.resolvedMediaURL(raw) ?? URL(string: raw)
    }

    /// Cloudinary dish-hero URL for list rows when MP4 playback is unavailable.
    private var listHeroCloudinaryFallbackURL: URL? {
        guard let raw = asset.premiumCloudinaryUrl else { return nil }
        return SmartThumbnailCloudinary.resizedURL(from: raw, width: Int(side), height: Int(side))
    }

    // MARK: - Shared UI

    private func localImageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .opacity(imageVisible ? 1 : 0)
            .transition(.opacity.animation(.easeIn(duration: 0.2)))
            .onAppear {
                revealImage()
            }
    }

    private var loadingView: some View {
        ZStack {
            placeholderBackground
            ProgressView()
                .tint(AppTheme.primary)
        }
    }

    private var failureView: some View {
        ZStack {
            placeholderBackground
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.55))
        }
    }

    private var placeholderBackground: some View {
        Color(.systemGray5)
    }

    @MainActor
    private func revealImage() {
        withAnimation(.easeIn(duration: 0.2)) {
            imageVisible = true
        }
    }

    @MainActor
    private func resetState() {
        freeTierImage = nil
        isLoadingFreeTier = false
        hasFailed = false
        imageVisible = false
    }
}

// MARK: - Kingfisher cache bridge

enum SmartThumbnailCache {
    static func cachedImage(forKey key: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            ImageCache.default.retrieveImage(forKey: key) { result in
                switch result {
                case .success(let value) where value.image != nil:
                    continuation.resume(returning: value.image)
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func store(_ image: UIImage, forKey key: String) async {
        await withCheckedContinuation { continuation in
            ImageCache.default.store(image, forKey: key, toDisk: true) { _ in
                continuation.resume()
            }
        }
    }
}

// MARK: - Recipe convenience wrapper

struct SmartRecipeListThumbnailView: View {
    let recipe: Recipe
    var side: CGFloat = 72
    @ObservedObject private var subManager = SubscriptionManager.shared

    var body: some View {
        SmartThumbnailView(
            asset: SmartThumbnailAsset(recipe: recipe),
            isUserPremium: subManager.isPremium,
            side: side,
            cornerRadius: AppTheme.boxCornerRadius
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius)
                .stroke(AppTheme.textSecondary.opacity(0.28), lineWidth: AppTheme.boxBorderWidth)
        )
    }
}

#Preview("Smart thumbnail") {
    SmartThumbnailView(
        asset: SmartThumbnailAsset(
            thumbId: "preview-thumb",
            videoUrlString: "https://example.com/video.mp4",
            timestampSeconds: 5.5,
            premiumCloudinaryUrl: "https://res.cloudinary.com/demo/image/upload/sample.jpg"
        ),
        isUserPremium: true
    )
    .padding()
}
