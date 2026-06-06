import SwiftUI
import SwiftData

/// Cook mode intro — steps card only (no outer media frame), bottom clipped, flashing 👆.
struct OnboardingRecipePageStepsSlideView: View {
    var onStepsTapped: () -> Void = {}

    @State private var recipe: Recipe?
    @State private var showPointer = false

    var body: some View {
        VStack(spacing: 10) {
            Text("⑧ Tap Steps To Enter Cook Mode")
                .appFont(.titleBold)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
                .padding(.top, 4)

            Group {
                if let recipe {
                    ZStack(alignment: .bottom) {
                        Color.clear
                            .aspectRatio(OnboardingMediaLayout.aspectRatio, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .overlay {
                                ScrollView {
                                    OnboardingRecipeStepsSectionView(stepLines: recipe.stepLines)
                                        .padding(16)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            onStepsTapped()
                                        }
                                }
                                .scrollIndicators(.hidden)
                                .scrollDisabled(true)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .background(AppTheme.surface)
                            }
                            .clipShape(
                                RoundedRectangle(cornerRadius: OnboardingMediaLayout.cornerRadius, style: .continuous)
                            )
                            .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)

                        OnboardingFlashingPointerEmojiView(emoji: "👆", fontSize: 56)
                            .padding(.bottom, 28)
                            .opacity(showPointer ? 1 : 0)
                            .scaleEffect(showPointer ? 1 : 0.9)
                            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: showPointer)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
        .onAppear {
            if recipe == nil, let pair = OnboardingImportStepMockData.makePreviewContainer() {
                recipe = pair.1
            }
            showPointer = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showPointer = true
            }
        }
        .onDisappear {
            showPointer = false
        }
    }
}

#Preview {
    OnboardingRecipePageStepsSlideView()
        .background(Color(.systemBackground))
}
