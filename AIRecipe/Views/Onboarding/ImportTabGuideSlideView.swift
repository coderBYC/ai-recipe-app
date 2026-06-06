import SwiftUI

/// Step 6: Imports tab with a ready recipe row.
struct ImportTabGuideSlideView: View {
    let recipeTitle: String

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    OnboardingCoachmark(text: OnboardingStep.importTapRecipe.coachmark)
                        .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Imports")
                            .appFont(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(AppTheme.primary)

                        demoImportRow
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)

            onboardingTabBar(highlight: .imports)
        }
    }

    private var demoImportRow: some View {
        let demoRecipe = OnboardingImportStepMockData.makeRecipe()

        return HStack(spacing: 14) {
            RecipeListThumbnailView(recipe: demoRecipe)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipeTitle)
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                Text("Ready · TikTok")
                    .appFont(.caption)
                    .foregroundStyle(.green)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(12)
        .boxStyle(cornerRadius: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.primary, lineWidth: 2)
        )
    }

    private enum HighlightTab {
        case imports
    }

    private func onboardingTabBar(highlight: HighlightTab) -> some View {
        HStack(spacing: 0) {
            tabItem(icon: "house.fill", title: "Home", selected: false)
            tabItem(icon: "square.and.arrow.up", title: "Imports", selected: highlight == .imports)
            Color.clear.frame(width: 52, height: 52)
            tabItem(icon: "calendar", title: "Plan", selected: false)
            tabItem(icon: "gearshape.fill", title: "Settings", selected: false)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(AppTheme.cardBackground)
    }

    private func tabItem(icon: String, title: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppTheme.bitterFont(size: 20, weight: selected ? .bold : .regular))
            Text(title)
                .appFont(.caption2)
        }
        .foregroundStyle(selected ? AppTheme.primary : AppTheme.textSecondary)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            if selected {
                Capsule()
                    .fill(AppTheme.primary)
                    .frame(width: 28, height: 3)
                    .offset(y: -6)
            }
        }
    }
}
