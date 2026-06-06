//
//  OnboardingView.swift
//  AIRecipeApp
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentStep: OnboardingStep
    @State private var slideDirection: OnboardingSlideDirection = .forward

    init(startingAt step: OnboardingStep = .intro) {
        _currentStep = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressBar(currentStep: currentStep)

            ZStack {
                OnboardingSlideCanvas(direction: slideDirection) {
                    OnboardingStepSlideView(
                        step: currentStep,
                        onAuthenticated: completeOnboarding,
                        onImportTabFlowCompleted: autoAdvanceFromImportTabStep,
                        onCookModeVoiceDemoCompleted: autoAdvanceFromCookModeVoiceStep
                    )
                    .id(currentStep.slideIdentity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            OnboardingNavigationBar(
                currentStep: $currentStep,
                onNext: { advanceStep(direction: .forward) },
                onBack: { regressStep(direction: .backward) }
            )
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if currentStep.isSignInStep, value.translation.width < -threshold { return }
                    if value.translation.width < -threshold {
                        advanceStep(direction: .forward)
                    } else if value.translation.width > threshold {
                        regressStep(direction: .backward)
                    }
                }
        )
        .onAppear {
            if authManager.authState == .authenticated, currentStep == .signInAuth {
                completeOnboarding()
            }
        }
    }

    private func advanceStep(direction: OnboardingSlideDirection) {
        if currentStep == .signInAuth { return }

        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            completeOnboarding()
            return
        }
        slideDirection = direction
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            currentStep = next
        }
    }

    private func regressStep(direction: OnboardingSlideDirection) {
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        slideDirection = direction
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            currentStep = prev
        }
    }

    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.4)) {
            hasCompletedOnboarding = true
        }
    }

    private func autoAdvanceFromImportTabStep() {
        let interactiveSteps: Set<OnboardingStep> = [
            .recipeDoneNotification,
            .importTapRecipe,
            .recipePageTapSteps,
        ]
        guard interactiveSteps.contains(currentStep) else { return }
        advanceStep(direction: .forward)
    }

    private func autoAdvanceFromCookModeVoiceStep() {
        guard currentStep == .cookModeVoiceIntro else { return }
        advanceStep(direction: .forward)
    }
}

#Preview {
    OnboardingView()
        .environment(AuthManager(service: SupabaseService.shared))
        .modelContainer(for: Recipe.self, inMemory: true)
}
