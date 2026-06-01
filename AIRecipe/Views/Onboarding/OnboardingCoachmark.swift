import SwiftUI

/// Neobrutalist coach label — customize via `OnboardingCoachSpec` in `OnboardingState`.
struct OnboardingCoachmark: View {
    let spec: OnboardingCoachSpec

    init(_ spec: OnboardingCoachSpec) {
        self.spec = spec
    }

    init(text: String) {
        self.spec = OnboardingCoachSpec(text: text)
    }

    var body: some View {
        Text(spec.text)
            .appFont(spec.font)
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(spec.textAlignment)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .padding(.horizontal, spec.paddingHorizontal)
            .padding(.vertical, spec.paddingVertical)
            .boxStyle(cornerRadius: spec.cornerRadius)
    }

    private var frameAlignment: Alignment {
        switch spec.textAlignment {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        OnboardingCoachmark(OnboardingStep.intro.coach)
        OnboardingCoachmark(OnboardingStep.shareRecipe.coach)
    }
    .padding(20)
    .background(AppTheme.surface)
}
