import SwiftUI
import SwiftData
import UIKit

/// Cook Mode preview + centered voice prompts; advances when timer hits 5:00 then step changes.
struct OnboardingCookModeIntroSlideView: View {
    var onVoiceDemoCompleted: () -> Void = {}

    @State private var previewContainer: ModelContainer?
    @State private var recipe: Recipe?
    @State private var demoPhase: VoiceDemoPhase = .idle
    @State private var demoTrigger: OnboardingCookModeDemoTrigger = .none
    @State private var promptRevealed = false
    @State private var didFinishFiveMinutePhase = false
    @State private var didFinishNextPhase = false
    @State private var transitionTask: Task<Void, Never>?
    @State private var voiceIsListening = false
    @State private var voiceAuthorizationDenied = false
    @State private var voiceStatusText = ""
    @State private var cookModeInstanceID = UUID()

    private enum VoiceDemoPhase {
        case idle
        case sayFiveMinutes
        case sayNext
        case finished
    }

    private static let fiveMinuteTimerSeconds = 5 * 60
    private static let phasePause: Duration = .seconds(1)
    private static let spring = Animation.spring(response: 0.5, dampingFraction: 0.82)

    var body: some View {
        VStack(spacing: 12) {
            Text("⑨ Voice Comand Allows You To Set Timer And Cook Step By Step")
                .padding(.horizontal, 20)
                .appFont(.titleBold)

            ZStack {
                OnboardingMediaBox {
                    Group {
                        if let recipe {
                            CookModeView(
                                recipe: recipe,
                                onboardingVoiceShortcuts: false,
                                enablesVoiceAssistant: true,
                                onboardingDemoTrigger: demoTrigger,
                                onOnboardingCookStateChange: handleCookStateChange,
                                onOnboardingVoiceStatusChange: handleVoiceStatusChange
                            )
                            .id(cookModeInstanceID)
                            .clipShape(RoundedRectangle(cornerRadius: OnboardingMediaLayout.cornerRadius, style: .continuous))
                        } else {
                            Color.black
                                .overlay {
                                    ProgressView()
                                        .tint(.white)
                                }
                        }
                    }
                }
                .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)

                cookModeVoicePromptOverlay

                if voiceAuthorizationDenied {
                    voicePermissionOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if previewContainer == nil, let pair = OnboardingImportStepMockData.makePreviewContainer() {
                previewContainer = pair.0
                recipe = pair.1
            }
        }
        .task {
            await beginVoiceDemo()
        }
        .onDisappear {
            transitionTask?.cancel()
            resetDemo()
        }
        .modifier(OnboardingCookModePreviewModelContainer(container: previewContainer))
    }

    @ViewBuilder
    private var cookModeVoicePromptOverlay: some View {
        if demoPhase == .sayFiveMinutes || demoPhase == .sayNext {
            Button {
                handlePromptTap()
            } label: {
                VStack(spacing: 10) {
                    voicePromptLabel
                    voiceListeningHint
                    OnboardingVoiceWaveformView(isActive: promptRevealed && (voiceIsListening || voiceAuthorizationDenied))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 10)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius)
                        .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
                )
                .shadow(color: AppTheme.shadow, radius: 0, x: 4, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .opacity(promptRevealed ? 1 : 0)
            .scaleEffect(promptRevealed ? 1 : 0.94)
            .animation(Self.spring, value: promptRevealed)
            .animation(Self.spring, value: demoPhase)
            .accessibilityHint("Say the phrase out loud, or tap to try the command")
        }
    }

    @ViewBuilder
    private var voiceListeningHint: some View {
        if voiceAuthorizationDenied {
            Text("Turn on Microphone & Speech Recognition in Settings, then try again.")
                .appFont(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        } else if voiceIsListening {
            Text("Listening… say the phrase out loud")
                .appFont(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        } else if !voiceStatusText.isEmpty {
            Text(voiceStatusText)
                .appFont(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        } else {
            Text("Allow microphone & speech when iOS asks")
                .appFont(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var voicePermissionOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                OnboardingIOSPermissionAlert(
                    title: "“Let Him Cook” Would Like to Access Speech Recognition",
                    message: "Speech data from this app will be sent to Apple to process your requests. This lets Cook Mode hear “5 minutes” and “next.”"
                )

                Text("Tap OK on the system prompts. If you tapped Don’t Allow, open Settings to enable Microphone and Speech Recognition.")
                    .appFont(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                HStack(spacing: 12) {
                    Button {
                        cookModeInstanceID = UUID()
                    } label: {
                        Text("Try Again")
                            .appFont(.headlineBold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.2), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        openAppSettings()
                    } label: {
                        Text("Open Settings")
                            .appFont(.headlineBold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func handleVoiceStatusChange(isListening: Bool, denied: Bool, status: String) {
        voiceIsListening = isListening
        voiceAuthorizationDenied = denied
        voiceStatusText = status
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @ViewBuilder
    private var voicePromptLabel: some View {
        switch demoPhase {
        case .sayFiveMinutes:
            voicePromptText(phrase: "5 minutes")
        case .sayNext:
            voicePromptText(phrase: "Next")
        case .idle, .finished:
            EmptyView()
        }
    }

    private func voicePromptText(phrase: String) -> some View {
        HStack(spacing: 0) {
            Text("Say ")
                .appFont(.headlineBold)
            Text("\"\(phrase)\"")
                .appFont(.headlineBold)
                .foregroundStyle(AppTheme.primary)
        }
        .foregroundStyle(AppTheme.textPrimary)
        .multilineTextAlignment(.center)
    }

    private func handlePromptTap() {
        switch demoPhase {
        case .sayFiveMinutes:
            pulseDemoTrigger(.setFiveMinutes)
        case .sayNext:
            pulseDemoTrigger(.nextStep)
        case .idle, .finished:
            break
        }
    }

    private func pulseDemoTrigger(_ trigger: OnboardingCookModeDemoTrigger) {
        demoTrigger = trigger
        DispatchQueue.main.async {
            demoTrigger = .none
        }
    }

    private func handleCookStateChange(stepIndex: Int, timerSeconds: Int) {
        guard demoPhase != .finished else { return }

        if demoPhase == .sayFiveMinutes,
           !didFinishFiveMinutePhase,
           timerSeconds == Self.fiveMinuteTimerSeconds {
            didFinishFiveMinutePhase = true
            transitionTask?.cancel()
            transitionTask = Task { @MainActor in
                await transitionToSayNext()
            }
        }

        if demoPhase == .sayNext,
           !didFinishNextPhase,
           stepIndex >= 1 {
            didFinishNextPhase = true
            transitionTask?.cancel()
            transitionTask = Task { @MainActor in
                await transitionToMealPlan()
            }
        }
    }

    @MainActor
    private func beginVoiceDemo() async {
        resetDemo()

        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            demoPhase = .sayFiveMinutes
            withAnimation(Self.spring) { promptRevealed = true }
            return
        }

        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }

        demoPhase = .sayFiveMinutes
        withAnimation(Self.spring) { promptRevealed = true }
    }

    @MainActor
    private func transitionToSayNext() async {
        withAnimation(Self.spring) { promptRevealed = false }
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: Self.phasePause)
        guard !Task.isCancelled else { return }

        demoPhase = .sayNext
        withAnimation(Self.spring) { promptRevealed = true }
    }

    @MainActor
    private func transitionToMealPlan() async {
        withAnimation(Self.spring) { promptRevealed = false }
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: Self.phasePause)
        guard !Task.isCancelled else { return }

        demoPhase = .finished
        onVoiceDemoCompleted()
    }

    @MainActor
    private func resetDemo() {
        transitionTask?.cancel()
        transitionTask = nil
        demoPhase = .idle
        demoTrigger = .none
        promptRevealed = false
        didFinishFiveMinutePhase = false
        didFinishNextPhase = false
    }
}

private struct OnboardingCookModePreviewModelContainer: ViewModifier {
    let container: ModelContainer?

    func body(content: Content) -> some View {
        if let container {
            content.modelContainer(container)
        } else {
            content
        }
    }
}

#Preview {
    OnboardingCookModeIntroSlideView()
        .background(Color(.systemBackground))
}
