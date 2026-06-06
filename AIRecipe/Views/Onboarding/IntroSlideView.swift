import SwiftUI

struct IntroSlideView: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 20)

            VStack(spacing: 8) {
                Text("Welcome To")
                    .appFont(.largeTitle)
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Let Him Cook")
                    .appFont(.largeTitle)
                    .padding(.horizontal,24)
                    .padding(.vertical,16)
                    .boxStyle(cornerRadius: 15)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Image("saltbae")
                .resizable()
                .scaledToFit()
                .frame(width: 300, height: 300)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.top, 8)
                .clipped()

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
