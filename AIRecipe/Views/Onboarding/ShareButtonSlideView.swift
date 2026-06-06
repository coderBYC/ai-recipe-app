import SwiftUI

struct ShareButtonSlideView: View {
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            VStack(alignment: .center) {
                Text("① Tap Share Button")
                    .appFont(.largeTitle)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(" To Send Recipe")
                    .appFont(.largeTitle)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .slideInFromTop(order: 0, isRevealed: isRevealed)

            Image(systemName: "paperplane.fill")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 82, height: 80)
                .padding(.top, 10)
                .padding(.bottom, 40)
                .clipped()
                .cornerRadius(12)
                .slideInFromTop(order: 1, isRevealed: isRevealed)

            OnboardingFlashingArrowView(rotationDegrees: 70)
                .slideInFromTop(order: 2, isRevealed: isRevealed)

            Text("② Click Let Him Cook Icon")
                .appFont(.largeTitle)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
                .slideInFromTop(order: 3, isRevealed: isRevealed)
                .padding(.top,30)
                .padding(.bottom,20)

            VStack(alignment: .center) {
                Image("icon")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 150, height: 150)
                    .clipped()
                    .cornerRadius(25)
                Text("Let Him Cook")
                    .fontWeight(.medium)
                    .font(.system(size: 22))
                    .foregroundStyle(.gray)
                    .padding(.top, 0)
            }
            .slideInFromTop(order: 4, isRevealed: isRevealed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { playEntranceAnimation() }
    }

    private func playEntranceAnimation() {
        isRevealed = false
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                isRevealed = true
            }
        }
    }
}

private struct SlideInFromTopModifier: ViewModifier {
    let order: Int
    let isRevealed: Bool

    private var delay: Double { Double(order) * 0.11 }

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed ? 0 : -32)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.82).delay(delay),
                value: isRevealed
            )
    }
}

private extension View {
    func slideInFromTop(order: Int, isRevealed: Bool) -> some View {
        modifier(SlideInFromTopModifier(order: order, isRevealed: isRevealed))
    }
}

#Preview {
    ShareButtonSlideView()
}
