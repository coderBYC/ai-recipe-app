import SwiftUI
import TipKit

struct CookModeView: View {

    @Bindable var recipe: Recipe
    /// When true, shows tappable shortcuts that mirror voice timer commands (onboarding).
    var onboardingVoiceShortcuts: Bool = false
    /// When false, skips mic/speech setup (onboarding mock in media box).
    var enablesVoiceAssistant: Bool = true
    /// Scripted onboarding cues (advance step / set timer) without real speech.
    var onboardingDemoTrigger: OnboardingCookModeDemoTrigger = .none
    /// Reports step index + timer seconds for onboarding voice-demo detection.
    var onOnboardingCookStateChange: ((Int, Int) -> Void)? = nil
    /// Reports mic / speech status for onboarding permission UI.
    var onOnboardingVoiceStatusChange: ((Bool, Bool, String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = CookModeVoiceController()
    @State private var stepIndex: Int = 0
    @State private var timerSeconds: Int = 0
    @State private var isTimerRunning: Bool = false
    @ObservedObject private var subManager = SubscriptionManager.shared
    
    var steps: [String] {
        recipe.stepLines
    }

    /// Per-step thumbnails need a playable MP4 URL (not the Cloudinary dish-hero image).
    private var showsCookModeThumbnail: Bool {
        if recipe.downloadedVideoURL.hasPrefix("asset://") { return false }
        return !recipe.resolvedVideoPlaybackURLString.isEmpty
    }

    var body: some View {
        
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Background tap layer (doesn't block buttons)
            GeometryReader { _ in
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { previousStep() }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { nextStep() }
                }
            }
            
            VStack {
                
                // Top bar
                HStack {
                    if voice.isListening {
                        Image(systemName: "mic.fill")
                            .nanumAppFont(.caption)
                            .foregroundStyle(.green)
                    } else if voice.authorizationDenied {
                        Image(systemName: "mic.slash.fill")
                            .nanumAppFont(.caption)
                            .foregroundStyle(.orange.opacity(0.9))
                    }
                    if !voice.statusText.isEmpty {
                        Text(voice.statusText)
                            .nanumAppFont(.caption2)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .nanumAppFont(.callout)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                    }


                }
                .padding()
                
                // Progress bars
                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i <= stepIndex ? Color.white : Color.gray.opacity(0.4))
                            .frame(height: 6)
                            
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 12)

                if !steps.isEmpty {
                    VStack(spacing: 20) {
                        // Dish hero thumbnail above step text (premium Cloudinary / free local capture).
                        if showsCookModeThumbnail {
                            SmartThumbnailView(
                                asset: SmartThumbnailAsset(recipe: recipe, mode: .cookModeStep(stepIndex)),
                                isUserPremium: subManager.isPremium,
                                mode: .cookModeStep(stepIndex),
                                side: 120,
                                cornerRadius: 12
                            )
                            .id(stepIndex)
                        }

                        Text(steps[stepIndex])
                            .nanumAppFont(.largeTitle)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                }

                Spacer(minLength: 12)
                
                // Timer controls
                VStack(spacing: 8) {
                    Text(timeString(from: timerSeconds))
                        .font(AppTheme.nanumMyeongjoFont(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                       

                    if onboardingVoiceShortcuts {
                        VStack(spacing: 6) {
                            Text("Or tap to practice the same commands")
                                .nanumAppFont(.caption2)
                                .foregroundStyle(.white.opacity(0.75))
                            HStack(spacing: 10) {
                                Button("5 minutes") {
                                    handleIssuedCommand(.setMinutes(5))
                                    voice.resetIssuedCommand()
                                }
                                .nanumAppFont(.caption)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white, in: Capsule())

                                Button("Pause") {
                                    handleIssuedCommand(.pauseTimer)
                                    voice.resetIssuedCommand()
                                }
                                .nanumAppFont(.caption)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white, in: Capsule())
                            }
                        }
                        .padding(.top, 4)
                    }

                    HStack(spacing: 16) {
                        Button {
                            if timerSeconds >= 10 { timerSeconds -= 10 }
                        } label: {
                            Text("-10s")
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Color.white, in: Capsule())
                        }
                        
                        Button {
                            isTimerRunning.toggle()
                        } label: {
                            Text(isTimerRunning ? "Pause" : "Start")
                                .foregroundStyle(.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.white, in: Capsule())
                        }
                      
                        
                        Button {
                            timerSeconds += 10
                        } label: {
                            Text("+10s")
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Color.white, in: Capsule())
                        }
                    }
                    .nanumAppFont(.body)
                }
                .padding(.bottom, 16)
                
                // Step counter
                Text("\(stepIndex + 1) / \(steps.count)")
                    .nanumAppFont(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 24)
            }
        }
        // Swipe left/right to navigate steps
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.width < -threshold {
                        nextStep()
                    } else if value.translation.width > threshold {
                        previousStep()
                    }
                }
        )
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if isTimerRunning, timerSeconds > 0 {
                timerSeconds -= 1
            } else if isTimerRunning, timerSeconds == 0 {
                isTimerRunning = false
            }
        }
        .onAppear {
            if enablesVoiceAssistant {
                voice.requestPermissionsAndStart()
            }
            reportOnboardingCookState()
            reportOnboardingVoiceStatus()
        }
        .onDisappear {
            voice.stop()
        }
        .onChange(of: voice.issuedCommand) { _, cmd in
            handleIssuedCommand(cmd)
            if cmd != .none {
                voice.resetIssuedCommand()
            }
            reportOnboardingVoiceStatus()
        }
        .onChange(of: voice.isListening) { _, _ in
            reportOnboardingVoiceStatus()
        }
        .onChange(of: voice.authorizationDenied) { _, _ in
            reportOnboardingVoiceStatus()
        }
        .onChange(of: voice.statusText) { _, _ in
            reportOnboardingVoiceStatus()
        }
        .onChange(of: onboardingDemoTrigger) { _, trigger in
            switch trigger {
            case .none:
                break
            case .nextStep:
                nextStep()
            case .setFiveMinutes:
                handleIssuedCommand(.setMinutes(5))
            }
            reportOnboardingCookState()
        }
        .onChange(of: stepIndex) { _, _ in
            reportOnboardingCookState()
        }
        .onChange(of: timerSeconds) { _, _ in
            reportOnboardingCookState()
        }
    }

    private func reportOnboardingCookState() {
        onOnboardingCookStateChange?(stepIndex, timerSeconds)
    }

    private func reportOnboardingVoiceStatus() {
        onOnboardingVoiceStatusChange?(voice.isListening, voice.authorizationDenied, voice.statusText)
    }

    private func handleIssuedCommand(_ cmd: CookVoiceCommand) {
        switch cmd {
        case .none:
            break
        case .next:
            nextStep()
        case .back:
            previousStep()
        case .setMinutes(let m):
            timerSeconds = m * 60
            isTimerRunning = true
        case .pauseTimer:
            isTimerRunning = false
        case .resumeTimer:
            if timerSeconds > 0 {
                isTimerRunning = true
            }
        }
    }

    func nextStep() {
        if stepIndex < steps.count - 1 {
            stepIndex += 1
        }
    }
    
    func previousStep() {
        if stepIndex > 0 {
            stepIndex -= 1
        }
    }
    
    private func timeString(from totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - TipKit (onboarding cook mode only)

private struct OnboardingCookPopoverTipModifier<T: Tip>: ViewModifier {
    let enabled: Bool
    let tip: T
    var edge: Edge = .top

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.popoverTip(tip, arrowEdge: edge)
        } else {
            content
        }
    }
}

private extension View {
    func onboardingCookTipIfNeeded<T: Tip>(_ enabled: Bool, tip: T, edge: Edge = .top) -> some View {
        modifier(OnboardingCookPopoverTipModifier(enabled: enabled, tip: tip, edge: edge))
    }
}

