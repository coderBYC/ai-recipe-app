import SwiftUI

enum OnboardingCoachArrowDirection {
    case up
    case down
}

struct OnboardingCoachCallout: View {
    let text: String
    var direction: OnboardingCoachArrowDirection = .down

    var body: some View {
        VStack(spacing: 0) {
            if direction == .up {
                pointer
            }

            Text(text)
                .appFont(.headlineBold)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)

            if direction == .down {
                pointer
            }
        }
        .zIndex(999)
        .allowsHitTesting(false)
    }

    private var pointer: some View {
        OnboardingCoachTriangle()
            .fill(AppTheme.surface)
            .frame(width: 16, height: 8)
            .overlay(
                OnboardingCoachTriangle()
                    .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
            )
            .offset(y: direction == .down ? -1 : 1)
    }
}

private struct OnboardingCoachTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
