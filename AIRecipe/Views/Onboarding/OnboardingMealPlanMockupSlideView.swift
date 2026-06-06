import SwiftUI
import UIKit

private struct LunchButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Spotlight tuning (edit when the cutout misses the lunch cell)

private enum OnboardingMealPlanSpotlightLayout {
    static let grayOpacity: Double = 0.78
    static let holeCornerRadius: CGFloat = 10

    static let useManualHolePlacement = false
    static let manualHoleCenterX: CGFloat = 0.62
    static let manualHoleCenterY: CGFloat = 0.58
    static let manualHoleWidth: CGFloat = 200
    static let manualHoleHeight: CGFloat = 44

    static let holeWidthPadding: CGFloat = 6
    static let holeHeightPadding: CGFloat = 6
    static let holeCenterXOffset: CGFloat = 0
    static let holeCenterYOffset: CGFloat = 0

    static let coachGapAboveButton: CGFloat = 48

    static func resolvedHole(lunchRect: CGRect, containerSize: CGSize) -> (center: CGPoint, size: CGSize) {
        if useManualHolePlacement {
            return (
                CGPoint(x: containerSize.width * manualHoleCenterX, y: containerSize.height * manualHoleCenterY),
                CGSize(width: manualHoleWidth, height: manualHoleHeight)
            )
        }
        return (
            CGPoint(x: lunchRect.midX + holeCenterXOffset, y: lunchRect.midY + holeCenterYOffset),
            CGSize(width: lunchRect.width + holeWidthPadding, height: lunchRect.height + holeHeightPadding)
        )
    }
}

struct OnboardingMealPlanMockupSlideView: View {
    let onRecipeSelected: () -> Void

    @State private var showPicker = false
    @State private var selectedRecipe: String?
    @State private var didComplete = false
    @State private var contentRevealed = false
    @State private var showSpotlight = false
    @State private var showPointer = false
    @State private var showBottomPrompt = false

    private static let bottomPromptText = "Add anything in your weekly meal plan"
    private static let contentEntrance = Animation.spring(response: 0.55, dampingFraction: 0.84)
    private static let spotlightEntrance = Animation.easeInOut(duration: 0.45)
    private static let hintEntrance = Animation.spring(response: 0.5, dampingFraction: 0.82)

    private let sampleRecipes: [MockRecipeOption] = [
        .init(title: "Spicy Salmon Rice Bowl", creator: "@fitfoodie"),
        .init(title: "Chicken Caesar Wrap", creator: "@quickmeals"),
        .init(title: "Pesto Pasta Salad", creator: "@homecookingdaily"),
        .init(title: "Honey Garlic Tofu Bowl", creator: "@plantpoweredchef"),
        .init(title: "Steak Burrito Bowl", creator: "@kitchenreels"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            OnboardingMediaBox {
                ZStack {
                    mealPlanContent
                }
                .overlayPreferenceValue(LunchButtonAnchorKey.self) { anchor in
                    spotlightAndHintsOverlay(anchor: anchor)
                }
            }
            .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)

            if showBottomPrompt {
                OnboardingFlashingCoachBox(text: Self.bottomPromptText)
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await runEntranceSequence()
        }
        .onDisappear {
            contentRevealed = false
            showSpotlight = false
            showPointer = false
            showBottomPrompt = false
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                List(sampleRecipes) { recipe in
                    Button {
                        selectedRecipe = recipe.title
                        showPicker = false
                        completeStepIfNeeded()
                    } label: {
                        HStack(spacing: 12) {
                            SourceIconView(source: .instagram)
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.title)
                                    .appFont(.body)
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                Text(recipe.creator)
                                    .appFont(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Choose Lunch Recipe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showPicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var mealPlanContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meal Plan")
                .appFont(.titleBold)
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(contentRevealed ? 1 : 0)
                .offset(y: contentRevealed ? 0 : -12)
                .animation(Self.contentEntrance, value: contentRevealed)

            weekNavigator
                .opacity(contentRevealed ? 1 : 0)
                .offset(y: contentRevealed ? 0 : -10)
                .animation(Self.contentEntrance.delay(0.05), value: contentRevealed)

            dayStrip
                .opacity(contentRevealed ? 1 : 0)
                .offset(y: contentRevealed ? 0 : -8)
                .animation(Self.contentEntrance.delay(0.1), value: contentRevealed)

            dayCard(
                title: "Monday",
                date: "May 18",
                breakfast: "Bacon Steak BLT",
                lunch: selectedRecipe,
                dinner: "Steamed Spicy Fish Head",
                lunchInteractive: true,
                cardRevealed: contentRevealed,
                cardEntranceDelay: 0.14
            )

            dayCard(
                title: "Tuesday",
                date: "May 19",
                breakfast: "Crunchwrap Supreme",
                lunch: nil,
                dinner: nil,
                lunchInteractive: false,
                cardRevealed: contentRevealed,
                cardEntranceDelay: 0.22
            )

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppTheme.surface)
    }

    @ViewBuilder
    private func spotlightAndHintsOverlay(anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.gray.opacity(showSpotlight ? OnboardingMealPlanSpotlightLayout.grayOpacity : 0)

                if showSpotlight, let anchor {
                    let lunchRect = proxy[anchor]
                    let hole = OnboardingMealPlanSpotlightLayout.resolvedHole(lunchRect: lunchRect, containerSize: size)

                    RoundedRectangle(cornerRadius: OnboardingMealPlanSpotlightLayout.holeCornerRadius)
                        .frame(width: hole.size.width, height: hole.size.height)
                        .position(x: hole.center.x, y: hole.center.y)
                        .blendMode(.destinationOut)
                }

                if showPointer, let anchor {
                    let lunchRect = proxy[anchor]
                    OnboardingFlashingPointerEmojiView(emoji: "👇", fontSize: 44)
                        .position(x: lunchRect.midX, y: max(24, lunchRect.minY - 22))
                        .transition(.opacity.combined(with: .scale(scale: 0.88)))
                }
            }
            .compositingGroup()
            .allowsHitTesting(false)
            .animation(Self.spotlightEntrance, value: showSpotlight)
            .animation(Self.hintEntrance, value: showPointer)
        }
    }

    private var weekNavigator: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            VStack(spacing: 4) {
                Text("May 18–24, 2026")
                    .appFont(.headlineBold)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("This Week")
                    .appFont(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green)
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(AppTheme.primary, lineWidth: 1)
                    )
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .allowsHitTesting(false)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .boxStyle(cornerRadius: 8)
    }

    private var dayStrip: some View {
        HStack(spacing: 8) {
            mockDayPill(label: "Mon", date: "18")
            mockDayPill(label: "Tue", date: "19")
            mockDayPill(label: "Wed", date: "20")
            mockDayPill(label: "Thu", date: "21")
            mockDayPill(label: "Fri", date: "22")
        }
        .allowsHitTesting(false)
    }

    private func mockDayPill(label: String, date: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .appFont(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text(date)
                .appFont(.headlineBold)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
        )
    }

    private func dayCard(
        title: String,
        date: String,
        breakfast: String?,
        lunch: String?,
        dinner: String?,
        lunchInteractive: Bool,
        cardRevealed: Bool,
        cardEntranceDelay: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .appFont(.headlineBold)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(date)
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            }

            mealRow(slot: .breakfast, recipeTitle: breakfast, showInstagramForRecipe: true)
            lunchRow(interactive: lunchInteractive)
            mealRow(slot: .dinner, recipeTitle: dinner, showInstagramForRecipe: true)
        }
        .padding(12)
        .boxStyle(cornerRadius: 8)
        .opacity(cardRevealed ? 1 : 0)
        .offset(y: cardRevealed ? 0 : 16)
        .animation(Self.contentEntrance.delay(cardEntranceDelay), value: cardRevealed)
    }

    private func lunchRow(interactive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: MealSlot.lunch.iconName)
                .font(AppTheme.bitterFont(size: 15, weight: .regular))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 24, alignment: .center)

            Text(MealSlot.lunch.label)
                .appFont(.callout)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 74, alignment: .leading)

            Group {
                if interactive {
                    Button {
                        guard contentRevealed else { return }
                        showPicker = true
                    } label: {
                        mealCellContent(
                            title: selectedRecipe ?? "Add recipe",
                            showInstagram: selectedRecipe != nil,
                            showPlus: selectedRecipe == nil
                        )
                    }
                    .buttonStyle(.plain)
                    .anchorPreference(key: LunchButtonAnchorKey.self, value: .bounds) { $0 }
                } else {
                    mealCellContent(title: "Add recipe", showInstagram: false, showPlus: true)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func mealRow(slot: MealSlot, recipeTitle: String?, showInstagramForRecipe: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: slot.iconName)
                .font(AppTheme.bitterFont(size: 15, weight: .regular))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 24, alignment: .center)

            Text(slot.label)
                .appFont(.callout)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 74, alignment: .leading)

            mealCellContent(
                title: recipeTitle ?? "Add recipe",
                showInstagram: recipeTitle != nil && showInstagramForRecipe,
                showPlus: recipeTitle == nil
            )
            .allowsHitTesting(false)
        }
    }

    private func mealCellContent(title: String, showInstagram: Bool, showPlus: Bool) -> some View {
        HStack {
            Text(title)
                .appFont(.body)
                .foregroundStyle(title == "Add recipe" ? AppTheme.textSecondary : AppTheme.textPrimary)
                .lineLimit(2)
            Spacer()
            if showInstagram {
                SourceIconView(source: .instagram)
                    .frame(width: 22, height: 22)
            } else if showPlus {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.65))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
        )
    }

    private func completeStepIfNeeded() {
        guard !didComplete else { return }
        didComplete = true
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
        onRecipeSelected()
    }

    @MainActor
    private func runEntranceSequence() async {
        contentRevealed = false
        showSpotlight = false
        showPointer = false
        showBottomPrompt = false

        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }

        withAnimation(Self.contentEntrance) {
            contentRevealed = true
        }

        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }

        withAnimation(Self.spotlightEntrance) {
            showSpotlight = true
        }

        try? await Task.sleep(for: .milliseconds(480))
        guard !Task.isCancelled else { return }

        withAnimation(Self.hintEntrance) {
            showPointer = true
            showBottomPrompt = true
        }
    }
}

private struct MockRecipeOption: Identifiable {
    let id = UUID()
    let title: String
    let creator: String
}

private struct TrianglePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    OnboardingMealPlanMockupSlideView(onRecipeSelected: {})
        .padding()
}
