import SwiftUI
import UIKit

struct FinalCTASlideView: View {
    var body: some View {
        VStack(spacing: 24) {
            OnboardingCoachmark(OnboardingStep.youAreDone.coach)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Spacer(minLength: 8)

            memeImage
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var memeImage: some View {
        if UIImage(named: "OnboardingHolUpMeme") != nil {
            Image("OnboardingHolUpMeme")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if UIImage(named: "LoadingMeme") != nil {
            Image("LoadingMeme")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Image(systemName: "face.smiling")
                .font(.system(size: 72))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}

#Preview {
    FinalCTASlideView()
}
