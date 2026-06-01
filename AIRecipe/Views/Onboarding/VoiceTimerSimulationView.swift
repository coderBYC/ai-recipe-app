import SwiftUI

/// Step 10: practice “5 minutes” timer + notification permission prompt.
struct VoiceTimerSimulationView: View {
    @Binding var timerText: String
    @Binding var isActive: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                OnboardingCoachmark(text: OnboardingStep.cookModeVoiceIntro.coachmark)
                    .padding(.horizontal, 20)

                VStack(spacing: 16) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)

                    Text("Try saying or tapping:")
                        .appFont(.callout)
                        .foregroundStyle(AppTheme.textSecondary)

                    Button {
                        applyFiveMinuteTimer()
                    } label: {
                        Text("“5 minutes”")
                            .appFont(.headlineBold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Text(timerText)
                        .font(AppTheme.bitterFont(size: 36, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()

                    if isActive {
                        Text("Timer running — you’ll get a notification when it ends.")
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .boxStyle(cornerRadius: 10)
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            }
        }
    }

    private func applyFiveMinuteTimer() {
        timerText = "5:00"
        isActive = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
