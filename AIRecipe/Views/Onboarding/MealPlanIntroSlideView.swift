import SwiftUI

/// Step 11: meal plan overview.
struct MealPlanIntroSlideView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                OnboardingCoachmark(text: OnboardingStep.mealPlanAddRecipe.coachmark)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Meal Plan")
                        .appFont(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)

                    Text("This Week")
                        .appFont(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    HStack(spacing: 8) {
                        ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                            Text(day)
                                .appFont(.caption)
                                .frame(width: 32, height: 32)
                                .background(
                                    day == "T" ? AppTheme.primary.opacity(0.15) : Color(white: 0.96),
                                    in: Circle()
                                )
                                .overlay(
                                    Circle()
                                        .stroke(day == "T" ? AppTheme.primary : Color.clear, lineWidth: 2)
                                )
                        }
                    }

                    Text("Plan breakfast, lunch, and dinner for the whole week — drag recipes into each slot.")
                        .appFont(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(16)
                .boxStyle(cornerRadius: 10)
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}
