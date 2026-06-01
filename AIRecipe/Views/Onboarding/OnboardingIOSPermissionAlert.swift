import SwiftUI

/// Visual match for the system speech / microphone permission sheets shown in Cook Mode.
struct OnboardingIOSPermissionAlert: View {
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, message == nil || message?.isEmpty == true ? 20 : 16)

            Divider()

            HStack(spacing: 0) {
                Text("Don’t Allow")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)

                Divider()
                    .frame(height: 44)

                Text("OK")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
        }
        .frame(maxWidth: 270)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 30, y: 16)
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.4).ignoresSafeArea()
        OnboardingIOSPermissionAlert(
            title: "“Let Him Cook” Would Like to Access Speech Recognition",
            message: "Speech data from this app will be sent to Apple to process your requests. Apple may store your requests to improve speech recognition."
        )
    }
}
