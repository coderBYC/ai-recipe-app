import SwiftUI
import TipKit

/// True when the meal planner is embedded in the first-run walkthrough (TipKit + copy).
struct IsOnboardingWalkthroughKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isOnboardingWalkthrough: Bool {
        get { self[IsOnboardingWalkthroughKey.self] }
        set { self[IsOnboardingWalkthroughKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func onboardingRecipeEditTip(_ active: Bool) -> some View {
        if active {
            self.popoverTip(OnboardingEditRecipeTip(), arrowEdge: .top)
        } else {
            self
        }
    }

    @ViewBuilder
    func onboardingReorderTip(_ active: Bool) -> some View {
        if active {
            self.popoverTip(OnboardingReorderTip(), arrowEdge: .bottom)
        } else {
            self
        }
    }

    @ViewBuilder
    func onboardingSaveEditsTip(_ active: Bool) -> some View {
        if active {
            self.popoverTip(OnboardingSaveEditsTip(), arrowEdge: .bottom)
        } else {
            self
        }
    }

    @ViewBuilder
    func onboardingMealPlanTip(_ active: Bool) -> some View {
        if active {
            self.popoverTip(OnboardingMealPlanAddTip(), arrowEdge: .top)
        } else {
            self
        }
    }
}
