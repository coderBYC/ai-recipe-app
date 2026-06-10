import SwiftUI
import UIKit

struct CookAssistantPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ComingSoonTabContent(
                title: "Let Him Cook",
                subtitle: "Your AI kitchen assistant — ask questions while you cook.",
                assetImage: "OnboardingHolUpMeme"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Let Him Cook")
                        .nanumAppFont(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
    }
}

struct ComingSoonTabContent: View {
    let title: String
    let subtitle: String
    var systemImage: String?
    var assetImage: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Group {
                if let assetImage, UIImage(named: assetImage) != nil {
                    Image(assetImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 56))
                        .foregroundStyle(AppTheme.primary)
                }
            }
            Text(title)
                .appFont(.title2)
                .foregroundStyle(AppTheme.textPrimary)
            Text(subtitle)
                .appFont(.callout)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Coming soon")
                .appFont(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(AppTheme.cardBackground, in: Capsule())
                .overlay(Capsule().stroke(Color.black, lineWidth: AppTheme.boxBorderWidth))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surface.ignoresSafeArea())
    }
}
