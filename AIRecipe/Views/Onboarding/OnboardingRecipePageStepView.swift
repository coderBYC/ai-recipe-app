import SwiftUI
import SwiftData

struct OnboardingRecipePageStepView: View {
    let onFlowCompleted: () -> Void
    private let preview = OnboardingImportStepMockData.makePreviewContainer()

    /// Tune these in preview to align the clear hole with the toolbar Edit button.
    private let editHoleWidth: CGFloat = 44
    private let editHoleHeight: CGFloat = 44
    private let editHoleTrailingInset: CGFloat = 52
    private let editHoleTopOffset: CGFloat = 22

    var body: some View {
        VStack(spacing: 20) {
            OnboardingMediaBox {
                Group {
                    if let preview {
                        OnboardingRecipePageView(
                            recipe: preview.1,
                            onDismiss: {},
                            onboardingSpotlight: .editButton,
                            onOnboardingEditTapped: onFlowCompleted
                        )
                        .modelContainer(preview.0)
                    } else {
                        Text("Couldn’t load preview.")
                            .appFont(.headline)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(AppTheme.surface)
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingRecipePageStepView(onFlowCompleted: {})
}
