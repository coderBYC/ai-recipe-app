import SwiftUI
import UIKit

/// Coach + looping bundle video (or screenshot / placeholder fallback).
struct OnboardingVideoSlideView: View {
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: 20) {
            OnboardingCoachmark(step.coach)
                .padding(.horizontal, 20)

            media
                .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var media: some View {
        if let video = step.bundleVideo {
            OnboardingMediaBox {
                LoopingVideoPlayer(
                    videoName: video.name,
                    videoType: video.ext,
                    videoGravity: .resizeAspect
                )
                .id("\(step.rawValue)-\(video.name).\(video.ext)")
            }
        } else if let imageName = step.screenshotAssetName, UIImage(named: imageName) != nil {
            OnboardingMediaBox {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            OnboardingMediaPlaceholder(
                systemImage: step.screenshotPlaceholderIcon,
                message: placeholderMessage
            )
        }
    }

    private var placeholderMessage: String {
        if let video = step.bundleVideo {
            return "Add “\(video.name).\(video.ext)” to the app target"
        }
        if let imageName = step.screenshotAssetName {
            return "Add “\(imageName)” to Assets"
        }
        return "Add media for this step"
    }
}
