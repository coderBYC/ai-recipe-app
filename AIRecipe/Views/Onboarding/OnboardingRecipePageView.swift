import SwiftUI
import SwiftData

/// Onboarding-only recipe review: matches `RecipePageView` layout inside the media block, no Discard / Add to Home bar.
struct OnboardingRecipePageView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var recipe: Recipe
    var onDismiss: () -> Void
    var onboardingSpotlight: OnboardingSpotlightTarget? = nil
    var onOnboardingEditTapped: (() -> Void)? = nil
    var onOnboardingCookTimePlusTapped: (() -> Void)? = nil
    var onOnboardingEditSaved: (() -> Void)? = nil
    var onOnboardingStepsTapped: (() -> Void)? = nil

    @State private var showingEdit = false

    private var isOnboardingWalkthrough: Bool { onboardingSpotlight != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.surface
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerRow
                        videoSection
                        estimateTimeSection
                        ingredientsSection
                        stepsSection
                        NoteSection
                        ratingSection
                        if !recipe.sourceURL.isEmpty {
                            openLinkSection
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .appFont(.callout)
                            .foregroundStyle(isOnboardingWalkthrough ? AppTheme.textSecondary.opacity(0.45) : AppTheme.textPrimary)
                    }
                    .disabled(isOnboardingWalkthrough)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let onOnboardingEditTapped {
                            onOnboardingEditTapped()
                        } else {
                            showingEdit = true
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .appFont(.callout)
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(8)
                    }
                    .onboardingSpotlightTarget(.editButton)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { } label: {
                        Image(systemName: "square.and.arrow.up")
                            .appFont(.callout)
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.45))
                    }
                    .disabled(true)
                }
            }
            .sheet(isPresented: $showingEdit) {
                RecipeEditView(
                    recipe: recipe,
                    onDismiss: { showingEdit = false },
                    onOnboardingCookTimePlusTapped: onOnboardingCookTimePlusTapped,
                    onOnboardingSaved: onOnboardingEditSaved
                )
            }
        }
    }

    private var headerRow: some View {
        Text(recipe.title.isEmpty ? "Recipe" : recipe.title)
            .appFont(.titleBold)
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }

    private var videoSection: some View {
        Image("salmon")
            .resizable()
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius)
                    .stroke(AppTheme.textSecondary.opacity(0.3), lineWidth: AppTheme.boxBorderWidth)
            )
    }

    private var estimateTimeSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .foregroundStyle(AppTheme.primary)
            if recipe.prepMinutes > 0 {
                Text("Prep: \(recipe.prepMinutes) min • Cook: \(recipe.estimatedCookingMinutes) min")
                    .appFont(.callout)
            } else {
                Text("Cook: \(recipe.estimatedCookingMinutes) min")
                    .appFont(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ingredients", systemImage: "basket.fill")
                .appFont(.headlineBold)
                .foregroundStyle(AppTheme.textSecondary)
            let lines = recipe.ingredientLines
            if lines.isEmpty {
                Text("No ingredients listed")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    ingredientRow(index: index, line: line, linesCount: lines.count)
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }

    private func ingredientRow(index: Int, line: String, linesCount: Int) -> some View {
        let checked = recipe.ingredientChecked(at: index)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .appFont(.title3)
                .foregroundStyle(checked ? AppTheme.triedBadge : AppTheme.textSecondary)
            Text(line)
                .appFont(.callout)
                .foregroundStyle(checked ? AppTheme.textSecondary : AppTheme.textPrimary)
                .strikethrough(checked)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Steps", systemImage: "list.number")
                    .appFont(.headlineBold)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            }

            let steps = recipe.stepLines
            if steps.isEmpty {
                Text("No steps listed")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                        stepRow(number: index + 1, text: text, isLast: index == steps.count - 1)
                        if index < steps.count - 1 {
                            stepTimelineGapConnector()
                        }
                    }
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
        .onboardingSpotlightTarget(.stepsSection)
        .contentShape(Rectangle())
        .onTapGesture {
            guard onboardingSpotlight == .stepsSection else { return }
            onOnboardingStepsTapped?()
        }
    }

    private static let stepTimelineSpacing: CGFloat = 16

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

    private var NoteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notes", systemImage: "note.text")
                .appFont(.headlineBold)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(recipe.notes)
                .appFont(.notes)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 72)
                .padding(12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .boxStyle()
    }

    private var ratingSection: some View {
        HStack(spacing: 10) {
            Text("Rate this recipe")
                .appFont(.body)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= recipe.rating ? "star.fill" : "star")
                        .foregroundStyle(star <= recipe.rating ? AppTheme.primary : AppTheme.textSecondary.opacity(0.4))
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }

    private var openLinkSection: some View {
        Link(destination: URL(string: recipe.sourceURL) ?? URL(string: "https://example.com")!) {
            HStack {
                Text("Open in \(recipe.sourceEnum.rawValue)")
                    .appFont(.headlineBold)
                    .foregroundStyle(.black)
                Image(systemName: "arrow.up.right")
                    .appFont(.caption)
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
        }
        .background(AppTheme.textSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius)
                .stroke(AppTheme.textSecondary.opacity(0.25), lineWidth: AppTheme.boxBorderWidth)
        )
    }
}
