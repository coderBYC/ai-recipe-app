import SwiftUI
import SwiftData

struct OnboardingRecipeEditPlusStepView: View {
    let onFlowCompleted: () -> Void
    private let preview = OnboardingImportStepMockData.makePreviewContainer()

    /// Tune in preview to align hole with Total Time / +1 button.
    private let holeWidth: CGFloat = 320
    private let holeHeight: CGFloat = 120
    private let holeCenterXOffset: CGFloat = 0
    private let holeCenterY: CGFloat = 248

    var body: some View {
        VStack(spacing: 20) {
            OnboardingMediaBox {
                Group {
                    if let preview {
                        RecipeEditView(
                            recipe: preview.1,
                            onDismiss: {},
                            onboardingSpotlight: .cookTimePlusButton,
                            onOnboardingCookTimePlusTapped: onFlowCompleted
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
                    let holeX = proxy.size.width / 2 + holeCenterXOffset
                    let holeY = holeCenterY

                    ZStack {
                        Color.gray.opacity(0.78)
                        RoundedRectangle(cornerRadius: 12)
                            .frame(width: holeWidth, height: holeHeight)
                            .position(x: holeX, y: holeY)
                            .blendMode(.destinationOut)
                        OnboardingCoachCallout(text: "Add +1 for cooking time")
                            .padding(.top, 120)
                            .padding(.trailing, 24)
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
    OnboardingRecipeEditPlusStepView(onFlowCompleted: {})
}
