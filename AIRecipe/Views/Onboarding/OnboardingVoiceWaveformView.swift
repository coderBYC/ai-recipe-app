import SwiftUI

/// Decorative listening waveform for onboarding voice demos.
struct OnboardingVoiceWaveformView: View {
    var isActive: Bool

    private static let barCount = 7
    private static let barWidth: CGFloat = 4
    private static let minHeight: CGFloat = 6
    private static let maxHeight: CGFloat = 26

    @State private var levels: [CGFloat] = Array(repeating: 0.35, count: barCount)

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.green)
                    .frame(width: Self.barWidth, height: Self.minHeight + levels[index] * (Self.maxHeight - Self.minHeight))
            }
        }
        .frame(height: Self.maxHeight)
        .opacity(isActive ? 1 : 0.35)
        .onAppear { refreshLevels(animated: false) }
        .onChange(of: isActive) { _, active in
            if active {
                refreshLevels(animated: true)
            } else {
                settleLevels()
            }
        }
        .onReceive(Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()) { _ in
            guard isActive else { return }
            refreshLevels(animated: true)
        }
    }

    private func refreshLevels(animated: Bool) {
        let next = (0..<Self.barCount).map { _ in CGFloat.random(in: 0.2...1) }
        if animated {
            withAnimation(.easeInOut(duration: 0.1)) {
                levels = next
            }
        } else {
            levels = next
        }
    }

    private func settleLevels() {
        withAnimation(.easeOut(duration: 0.2)) {
            levels = Array(repeating: 0.25, count: Self.barCount)
        }
    }
}

#Preview {
    OnboardingVoiceWaveformView(isActive: true)
        .padding()
}
