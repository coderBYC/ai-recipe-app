import SwiftUI

enum OnboardingSlideDirection {
    case forward
    case backward

    /// Instant swap — avoids previous slide sliding left under the next one.
    var transition: AnyTransition { .identity }
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
