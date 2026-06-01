import SwiftUI

/// Steps timeline card (matches `OnboardingRecipePageView.stepsSection`).
struct OnboardingRecipeStepsSectionView: View {
    let stepLines: [String]

    private static let stepTimelineSpacing: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Steps", systemImage: "list.number")
                    .appFont(.headlineBold)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            }

            if stepLines.isEmpty {
                Text("No steps listed")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stepLines.enumerated()), id: \.offset) { index, text in
                        stepRow(number: index + 1, text: text, isLast: index == stepLines.count - 1)
                        if index < stepLines.count - 1 {
                            stepTimelineGapConnector()
                        }
                    }
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }

    private func stepRow(number: Int, text: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("\(number)")
                    .appFont(.headlineBold)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black, in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)
            .frame(maxHeight: .infinity, alignment: .top)

            Text(text)
                .appFont(.callout)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    private func stepTimelineGapConnector() -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Color.black)
                .frame(width: 3, height: Self.stepTimelineSpacing)
                .frame(width: 32)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    OnboardingRecipeStepsSectionView(
        stepLines: OnboardingImportStepMockData.makeRecipe().stepLines
    )
    .padding()
}
