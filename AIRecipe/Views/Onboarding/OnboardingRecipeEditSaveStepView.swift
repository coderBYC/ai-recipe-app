import SwiftUI
import SwiftData

struct OnboardingRecipeEditSaveStepView: View {
    let onFlowCompleted: () -> Void
    private let preview = OnboardingImportStepMockData.makePreviewContainer()

    /// Tune in preview to align hole with the Save (checkmark) toolbar button.
    private let holeWidth: CGFloat = 44
    private let holeHeight: CGFloat = 44
    private let holeTrailingInset: CGFloat = 18
    private let holeTopOffset: CGFloat = 22

    var body: some View {
        VStack(spacing: 20) {
            OnboardingMediaBox {
                Group {
                    if let preview {
                        RecipeEditView(
                            recipe: preview.1,
                            onDismiss: {},
                            onboardingCoachText: ImportOnboardingCoachStep.tapSave.coachText,
                            onOnboardingSaved: onFlowCompleted
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
                GeometryReader { proxy in
                    let holeX = proxy.size.width - holeTrailingInset - holeWidth / 2
                    let holeY = holeTopOffset + holeHeight / 2

                    ZStack {
                        Color.gray.opacity(0.78)
                        RoundedRectangle(cornerRadius: 10)
                            .frame(width: holeWidth, height: holeHeight)
                            .position(x: holeX, y: holeY)
                            .blendMode(.destinationOut)
                        OnboardingCoachCallout(text: ImportOnboardingCoachStep.tapSave.coachText ?? "")
                            .padding(.top, 50)
                            .padding(.trailing, 22)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    .compositingGroup()
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
    OnboardingRecipeEditSaveStepView(onFlowCompleted: {})
}
