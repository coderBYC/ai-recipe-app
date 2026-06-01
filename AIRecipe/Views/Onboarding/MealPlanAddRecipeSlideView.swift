import SwiftUI

/// Step 12: tap tomorrow’s lunch slot to add the demo recipe.
struct MealPlanAddRecipeSlideView: View {
    let recipeTitle: String
    var onAdded: () -> Void

    @State private var didAdd = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                OnboardingCoachmark(text: OnboardingStep.mealPlanAddRecipe.coachmark)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Tomorrow")
                        .appFont(.headlineBold)
                        .foregroundStyle(AppTheme.textPrimary)

                    mealSlotRow(
                        slot: "Breakfast",
                        icon: "sun.horizon.fill",
                        filled: false
                    )
                    mealSlotRow(
                        slot: "Lunch",
                        icon: "sun.max.fill",
                        filled: didAdd,
                        highlight: !didAdd
                    )
                    mealSlotRow(
                        slot: "Dinner",
                        icon: "moon.stars.fill",
                        filled: false
                    )
                }
                .padding(14)
                .boxStyle(cornerRadius: 10)
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func mealSlotRow(slot: String, icon: String, filled: Bool, highlight: Bool = false) -> some View {
        Button {
            guard slot == "Lunch", !didAdd else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                didAdd = true
            }
            onAdded()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(AppTheme.bitterFont(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(slot)
                        .appFont(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    if filled {
                        Text(recipeTitle)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    } else if highlight {
                        Text("Tap to add your recipe")
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.primary)
                    } else {
                        Text("Empty")
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                    }
                }

                Spacer()

                if highlight && !filled {
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(AppTheme.primary)
                } else if filled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .background(
                highlight && !filled
                    ? AppTheme.primary.opacity(0.08)
                    : Color(white: 0.98)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        highlight && !filled ? AppTheme.primary : Color.black.opacity(0.15),
                        lineWidth: highlight && !filled ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(slot != "Lunch" || didAdd)
    }
}
