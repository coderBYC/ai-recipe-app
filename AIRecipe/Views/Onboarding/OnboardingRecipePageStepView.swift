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
                            onboardingCoachText: ImportOnboardingCoachStep.tapEdit.coachText,
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
            .overlay {
                ZStack {
                    Color.gray.opacity(0.78)
                    OnboardingCoachCallout(text: "Edit Your Recipe!")
                        .padding(.top, 8)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                .allowsHitTesting(false)
            }
            .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingRecipePageStepView(onFlowCompleted: {})
}
