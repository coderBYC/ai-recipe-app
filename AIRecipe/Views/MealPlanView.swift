import SwiftData
import SwiftUI

// MARK: - Calendar (ISO-style week: Monday first)

private extension Calendar {
    static var mealPlanner: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    static func mondayStart(of date: Date) -> Date {
        let cal = mealPlanner
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let start = cal.date(from: comps) ?? date
        return cal.startOfDay(for: start)
    }
}

// MARK: - Main

struct MealPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isOnboardingWalkthrough) private var isOnboardingWalkthrough
    @Query(sort: \PlannedMeal.weekStart) private var allPlanned: [PlannedMeal]
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]

    @State private var displayedWeekStart: Date = Calendar.mondayStart(of: Date())
    @State private var pickerTarget: MealPickerTarget?

    private let calendar = Calendar.mealPlanner

    private var weekPlans: [PlannedMeal] {
        allPlanned.filter { calendar.isDate($0.weekStart, inSameDayAs: displayedWeekStart) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekNavigator
                    dayStrip
                    ForEach(0..<7, id: \.self) { dayIndex in
                        dayCard(dayIndex: dayIndex)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .background(AppTheme.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Meal Plan")
                        .appFont(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .sheet(item: $pickerTarget) { target in
                RecipePickerSheet(
                    recipes: recipes,
                    onPick: { recipe in
                        assignRecipe(recipe, dayIndex: target.dayIndex, slot: target.slot)
                        pickerTarget = nil
                    },
                    onClear: {
                        assignRecipe(nil, dayIndex: target.dayIndex, slot: target.slot)
                        pickerTarget = nil
                    }
                )
            }
            .onboardingMealPlanTip(isOnboardingWalkthrough)
        }
    }

    private var weekNavigator: some View {
        HStack(spacing: 12) {
            Button {
                shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppTheme.bitterFont(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 4) {
                Text(weekRangeTitle)
                    .appFont(.headlineBold)
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                if calendar.isDate(displayedWeekStart, equalTo: Calendar.mondayStart(of: Date()), toGranularity: .day) {
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
            }
            .frame(maxWidth: .infinity)

            Button {
                shiftWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppTheme.bitterFont(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .boxStyle(cornerRadius: 8)
    }

    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    dayPill(dayIndex: i)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func dayPill(dayIndex: Int) -> some View {
        let d = dateForDay(dayIndex)
        let isToday = calendar.isDateInToday(d)
        let short = shortWeekday(d)
        let num = calendar.component(.day, from: d)

        return VStack(spacing: 6) {
            Text(short)
                .appFont(.caption)
                .foregroundStyle(isToday ? AppTheme.surface : AppTheme.textSecondary)
            Text("\(num)")
                .appFont(.headlineBold)
                .foregroundStyle(isToday ? AppTheme.surface : AppTheme.textPrimary)
        }
        .frame(minWidth: 48)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isToday ? AppTheme.primary : AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
        )
    }

    private func dayCard(dayIndex: Int) -> some View {
        let d = dateForDay(dayIndex)
        let isToday = calendar.isDateInToday(d)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(longWeekday(d))
                    .appFont(.title3)
                    .foregroundStyle(AppTheme.textPrimary)
                mediumDate(d)
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                if isToday {
                    Text("Today")
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
            }

            VStack(spacing: 10) {
                ForEach(MealSlot.allCases) { slot in
                    mealRow(dayIndex: dayIndex, slot: slot)
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: 8)
    }

    private func mealRow(dayIndex: Int, slot: MealSlot) -> some View {
        let planned = weekPlans.first { $0.dayIndex == dayIndex && $0.mealSlot == slot }

        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: slot.iconName)
                .font(AppTheme.bitterFont(size: 15, weight: .regular))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 28, alignment: .center)

            Text(slot.label)
                .appFont(.callout)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 78, alignment: .leading)

            Button {
                pickerTarget = MealPickerTarget(dayIndex: dayIndex, slot: slot)
            } label: {
                HStack(spacing: 8) {
                    if let r = planned?.recipe {
                        Text(r.title.isEmpty ? "Untitled" : r.title)
                            .appFont(.body)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        SourceIconView(source: RecipeSource(rawValue: r.source) ?? .youtube)
                            .frame(width: 22, height: 22)
                    } else {
                        Text("Add recipe")
                            .appFont(.body)
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var weekRangeTitle: String {
        guard let end = calendar.date(byAdding: .day, value: 6, to: displayedWeekStart) else { return "" }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        if calendar.component(.month, from: displayedWeekStart) == calendar.component(.month, from: end) {
            f.dateFormat = "MMMM d"
            let startStr = f.string(from: displayedWeekStart)
            f.dateFormat = "d, yyyy"
            let endStr = f.string(from: end)
            return "\(startStr)–\(endStr)"
        }
        f.dateFormat = "MMM d"
        let a = f.string(from: displayedWeekStart)
        f.dateFormat = "MMM d, yyyy"
        let b = f.string(from: end)
        return "\(a) – \(b)"
    }

    private func dateForDay(_ dayIndex: Int) -> Date {
        calendar.date(byAdding: .day, value: dayIndex, to: displayedWeekStart) ?? displayedWeekStart
    }

    private func shortWeekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private func longWeekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private func mediumDate(_ date: Date) -> Text {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return Text(verbatim: f.string(from: date))
    }

    private func shiftWeek(by weeks: Int) {
        if let d = calendar.date(byAdding: .weekOfYear, value: weeks, to: displayedWeekStart) {
            displayedWeekStart = Calendar.mondayStart(of: d)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func assignRecipe(_ recipe: Recipe?, dayIndex: Int, slot: MealSlot) {
        let ws = displayedWeekStart
        let toRemove = allPlanned.filter {
            calendar.isDate($0.weekStart, inSameDayAs: ws) && $0.dayIndex == dayIndex && $0.mealSlot == slot
        }
        for p in toRemove {
            modelContext.delete(p)
        }
        if let recipe {
            let entry = PlannedMeal(weekStart: ws, dayIndex: dayIndex, mealSlot: slot, recipe: recipe)
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }
}

// MARK: - Picker target / sheet

private struct MealPickerTarget: Identifiable, Hashable {
    let dayIndex: Int
    let slot: MealSlot

    var id: String { "\(dayIndex)-\(slot.rawValue)" }
}

private struct RecipePickerSheet: View {
    let recipes: [Recipe]
    let onPick: (Recipe) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Recipe] {
        guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return recipes }
        let q = search.lowercased()
        return recipes.filter {
            $0.title.lowercased().contains(q) || $0.creator.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(AppTheme.bitterFont(size: 28, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("No recipes yet")
                            .appFont(.headlineBold)
                        Text("Save recipes from Home, then pick them here.")
                            .appFont(.callout)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filtered) { recipe in
                            Button {
                                onPick(recipe)
                            } label: {
                                HStack(spacing: 12) {
                                    SourceIconView(source: RecipeSource(rawValue: recipe.source) ?? .youtube)
                                        .frame(width: 28, height: 28)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(recipe.title.isEmpty ? "Untitled" : recipe.title)
                                            .appFont(.body)
                                            .foregroundStyle(AppTheme.textPrimary)
                                        if !recipe.creator.isEmpty {
                                            Text(recipe.creator)
                                                .appFont(.caption)
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.surface)
                }
            }
            .background(AppTheme.surface.ignoresSafeArea())
            .navigationTitle("Choose recipe")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search recipes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        onClear()
                    } label: {
                        Text("Clear")
                    }
                }
            }
        }
    }
}

#Preview {
    let schema = Schema([Recipe.self, PlannedMeal.self, RecipeImportSubmission.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    return MealPlanView()
        .modelContainer(container)
}
