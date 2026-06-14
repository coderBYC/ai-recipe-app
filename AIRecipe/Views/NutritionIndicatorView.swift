import SwiftUI

struct MacroMetric: Identifiable {
    let id = UUID()
    let name: String
    let amount: String
    let color: Color
}

struct NutritionIndicatorView: View {
    let calories: Int
    let macros: [MacroMetric]

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(calories)")
                    .font(AppTheme.libreBaskervilleFont(size: 28, weight: .bold))
                Text("kcal")
                    .font(AppTheme.libreBaskervilleFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 12) {
                ForEach(macros) { macro in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(macro.color)
                            .frame(width: 8, height: 8)

                        Text(macro.name)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.textSecondary)

                        Text(macro.amount)
                            .appFont(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension Recipe {
    /// Per-serving nutrition populated by Pro AI import.
    var hasNutrition: Bool {
        nutritionCalories > 0
            || nutritionProteinGrams > 0
            || nutritionCarbsGrams > 0
            || nutritionFatGrams > 0
    }

    var nutritionMacroMetrics: [MacroMetric] {
        var metrics: [MacroMetric] = []
        if nutritionProteinGrams > 0 {
            metrics.append(MacroMetric(name: "Protein", amount: "\(nutritionProteinGrams)g", color: .blue))
        }
        if nutritionCarbsGrams > 0 {
            metrics.append(MacroMetric(name: "Carbs", amount: "\(nutritionCarbsGrams)g", color: .orange))
        }
        if nutritionFatGrams > 0 {
            metrics.append(MacroMetric(name: "Fat", amount: "\(nutritionFatGrams)g", color: .purple))
        }
        return metrics
    }
}
