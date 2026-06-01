import SwiftUI
import SwiftData

/// Cook Mode preview + scripted voice prompts at the bottom.
struct OnboardingCookModeIntroSlideView: View {
    var onVoiceDemoCompleted: () -> Void = {}

    @State private var previewContainer: ModelContainer?
    @State private var recipe: Recipe?
    @State private var demoPhase: VoiceDemoPhase = .idle
    @State private var demoTrigger: OnboardingCookModeDemoTrigger = .none
    @State private var promptRevealed = false

    private enum VoiceDemoPhase {
        case idle
        case sayNext
        case sayFiveMinutes
        case finished
    }

    private static let promptDuration: Duration = .seconds(1.5)
    private static let spring = Animation.spring(response: 0.5, dampingFraction: 0.82)

    var body: some View {
        VStack(spacing: 12) {
            Text("⑧ Voice Comand Allows You To Set Timer And Cook Step By Step")
                .padding(.horizontal, 20)
                .appFont(.titleBold)

            OnboardingMediaBox {
                Group {
                    if let recipe {
                        CookModeView(
                            recipe: recipe,
                            onboardingVoiceShortcuts: false,
                            enablesVoiceAssistant: false,
                            onboardingDemoTrigger: demoTrigger
                        )
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

            voicePromptFooter
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

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
            await runVoiceDemoSequence()
        }
        .onDisappear {
            demoPhase = .idle
            demoTrigger = .none
            promptRevealed = false
        }
        .modifier(OnboardingCookModePreviewModelContainer(container: previewContainer))
    }

    @ViewBuilder
    private var voicePromptFooter: some View {
        if demoPhase != .idle && demoPhase != .finished {
            VStack(spacing: 10) {
                voicePromptLabel
                OnboardingVoiceWaveformView(isActive: promptRevealed)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
            .opacity(promptRevealed ? 1 : 0)
            .offset(y: promptRevealed ? 0 : 12)
            .animation(Self.spring, value: promptRevealed)
            .animation(Self.spring, value: demoPhase)
        }
    }

    @ViewBuilder
    private var voicePromptLabel: some View {
        switch demoPhase {
        case .sayNext:
            voicePromptText(phrase: "Next")
        case .sayFiveMinutes:
            voicePromptText(phrase: "5 minutes")
        case .idle, .finished:
            EmptyView()
        }
    }

    private func voicePromptText(phrase: String) -> some View {
        HStack(spacing: 0) {
            Text("<Say ")
                .appFont(.headlineBold)
            Text("\"\(phrase)\"")
                .appFont(.headlineBold)
                .foregroundStyle(AppTheme.primary)
            Text(">")
                .appFont(.headlineBold)
        }
        .foregroundStyle(AppTheme.textPrimary)
        .multilineTextAlignment(.center)
    }

    @MainActor
    private func runVoiceDemoSequence() async {
        demoPhase = .idle
        demoTrigger = .none
        promptRevealed = false

        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            demoPhase = .sayFiveMinutes
            promptRevealed = true
            return
        }

        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }

        demoPhase = .sayNext
        demoTrigger = .nextStep
        withAnimation(Self.spring) { promptRevealed = true }
        try? await Task.sleep(for: Self.promptDuration)
        guard !Task.isCancelled else { return }

        withAnimation(Self.spring) { promptRevealed = false }
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }

        demoPhase = .sayFiveMinutes
        demoTrigger = .setFiveMinutes
        withAnimation(Self.spring) { promptRevealed = true }
        try? await Task.sleep(for: Self.promptDuration)
        guard !Task.isCancelled else { return }

        demoPhase = .finished
        promptRevealed = false
        onVoiceDemoCompleted()
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
