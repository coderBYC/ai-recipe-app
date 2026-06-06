import SwiftUI
import SwiftData

/// Full salmon recipe preview — no gray spotlight; shows what a finished import looks like.
struct OnboardingImportedRecipeShowcaseSlideView: View {
    @State private var previewContainer: ModelContainer?
    @State private var recipe: Recipe?
    @State private var showHeadlineHints = false

    private static let headlineSpring = Animation.spring(response: 0.5, dampingFraction: 0.82)

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                Text("You can import every video to recipes like this!")
                    .appFont(.titleBold)
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if showHeadlineHints {
                    OnboardingFlashingPointerEmojiView(emoji: "👇", fontSize: 48)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
            .padding(.top, 4)

            Group {
                if let recipe, let previewContainer {
                    OnboardingMediaBox {
                        OnboardingRecipePageView(
                            recipe: recipe,
                            onDismiss: {}
                        )
                        .modelContainer(previewContainer)
                    }
                    .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
        .onAppear {
            if previewContainer == nil, let pair = OnboardingImportStepMockData.makePreviewContainer() {
                previewContainer = pair.0
                recipe = pair.1
            }
            showHeadlineHints = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(Self.headlineSpring) {
                    showHeadlineHints = true
                }
            }
        }
        .onDisappear {
            showHeadlineHints = false
        }
    }
}

#Preview {
    OnboardingImportedRecipeShowcaseSlideView()
        .background(Color(.systemBackground))
}
