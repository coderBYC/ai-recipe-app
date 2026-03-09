import SwiftUI
import UIKit

/// Shows real brand icon from Assets (InstagramIcon, YouTubeIcon, TikTokIcon) when available, otherwise SF Symbol.
struct SourceIconView: View {
    let source: RecipeSource
    var body: some View {
        if let name = source.iconAssetName, UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: source.iconName)
                .font(.body)
        }
    }
}
