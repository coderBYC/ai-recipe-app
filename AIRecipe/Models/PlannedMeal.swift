import Foundation
import SwiftData

enum MealSlot: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        }
    }

    var iconName: String {
        switch self {
        case .breakfast: return "sun.horizon.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        }
    }
}

@Model
final class PlannedMeal {
    var id: UUID
    /// Monday 00:00 local for the week this slot belongs to.
    var weekStart: Date
    /// 0 = Monday … 6 = Sunday
    var dayIndex: Int
    var mealSlotRaw: String
    @Relationship(deleteRule: .nullify) var recipe: Recipe?

    init(weekStart: Date, dayIndex: Int, mealSlot: MealSlot, recipe: Recipe? = nil) {
        self.id = UUID()
        self.weekStart = weekStart
        self.dayIndex = dayIndex
        self.mealSlotRaw = mealSlot.rawValue
        self.recipe = recipe
    }

    var mealSlot: MealSlot {
        get { MealSlot(rawValue: mealSlotRaw) ?? .breakfast }
        set { mealSlotRaw = newValue.rawValue }
    }
}
