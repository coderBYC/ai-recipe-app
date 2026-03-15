import SwiftUI

struct CookModeView: View {

    @Bindable var recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex: Int = 0

    var steps: [String] {
        recipe.stepLines
    }

    var body: some View {

        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack {

                // Top bar
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.callout)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                    }
                     
                }
                .padding()

                // Progress bars
                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Rectangle()
                            .fill(i <= stepIndex ? Color.white : Color.gray.opacity(0.4))
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Step text
                if !steps.isEmpty {
                    Text(steps[stepIndex])
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                Spacer()

                // Step counter
                Text("\(stepIndex + 1) / \(steps.count)")
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 40)
            }
        }

        // Tap left/right navigation
        .contentShape(Rectangle())
        .overlay(
            HStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        previousStep()
                    }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        nextStep()
                    }
            }
        )
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
}
