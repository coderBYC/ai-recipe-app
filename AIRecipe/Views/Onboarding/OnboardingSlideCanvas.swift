import SwiftUI

enum OnboardingSlideDirection {
    case forward
    case backward

    var transition: AnyTransition {
        switch self {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
}

struct OnboardingSlideCanvas<Content: View>: View {
    let direction: OnboardingSlideDirection
    @ViewBuilder let content: () -> Content

    init(
        direction: OnboardingSlideDirection = .forward,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.direction = direction
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(direction.transition)
    }
}
