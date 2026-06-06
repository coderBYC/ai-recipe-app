import SwiftUI
import SwiftData

/// Import walkthrough — plain import list (5), then spotlight on Edit (6).
struct OnboardingImportWalkthroughView: View {
    let step: ImportOnboardingCoachStep
    let onFlowCompleted: () -> Void

    private let preview = OnboardingImportStepMockData.makePreviewContainer()

    private static let transitionAnimation = Animation.easeInOut(duration: 0.48)

    private var usesPlainPresentation: Bool {
        step == .tapImportRow
    }

    private var usesSpotlightPresentation: Bool {
        step == .tapEdit
    }

    var body: some View {
        Group {
            if usesPlainPresentation {
                mediaContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if usesSpotlightPresentation {
                spotlightContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mediaContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, usesPlainPresentation ? 0 : OnboardingMediaLayout.horizontalPadding)
        .padding(.top, usesPlainPresentation ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Self.transitionAnimation, value: step)
    }

    @ViewBuilder
    private var spotlightContent: some View {
        if let preview {
            switch step {
            case .tapEdit:
                OnboardingSpotlightStepLayout(
                    headline: ImportOnboardingCoachStep.tapEdit.slideTitle,
                    target: .editButton
                ) {
                    OnboardingRecipePageView(
                        recipe: preview.1,
                        onDismiss: {},
                        onboardingSpotlight: .editButton,
                        onOnboardingEditTapped: onFlowCompleted
                    )
                    .modelContainer(preview.0)
                }

            default:
                importPlaceholder
            }
        } else {
            importPlaceholder
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        switch step {
        case .tapImportRow:
            OnboardingImportTabStepView(
                usesPlainLayout: true,
                onFlowCompleted: onFlowCompleted
            )
        case .tapEdit:
            EmptyView()
        case .done:
            EmptyView()
        }
    }

    private var importPlaceholder: some View {
        Text("Couldn't load preview.")
            .appFont(.headline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.surface)
    }
}

#Preview("Import Walkthrough") {
    OnboardingImportWalkthroughView(step: .tapEdit, onFlowCompleted: {})
        .padding()
}
