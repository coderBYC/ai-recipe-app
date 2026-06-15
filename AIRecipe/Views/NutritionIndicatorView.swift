import SwiftUI

struct MacroMetric: Identifiable {
    let id = UUID()
    let name: String
    let amount: String
    let color: Color
}

private struct MacroRingSegment: Identifiable {
    let id = UUID()
    let start: Double
    let end: Double
    let color: Color
}

private struct MacroCalorieRing: View {
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int

    private var segments: [MacroRingSegment] {
        let proteinCal = Double(proteinGrams * 4)
        let carbsCal = Double(carbsGrams * 4)
        let fatCal = Double(fatGrams * 9)
        let total = proteinCal + carbsCal + fatCal
        guard total > 0 else { return [] }

        var result: [MacroRingSegment] = []
        var cursor = 0.0

        if proteinCal > 0 {
            let fraction = proteinCal / total
            result.append(MacroRingSegment(start: cursor, end: cursor + fraction, color: .blue))
            cursor += fraction
        }
        if carbsCal > 0 {
            let fraction = carbsCal / total
            result.append(MacroRingSegment(start: cursor, end: cursor + fraction, color: .orange))
            cursor += fraction
        }
        if fatCal > 0 {
            result.append(MacroRingSegment(start: cursor, end: 1, color: .purple))
        }
        return result
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 7)

            ForEach(segments) { segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(
                        segment.color,
                        style: StrokeStyle(lineWidth: 7, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

struct NutritionIndicatorView: View {
    let calories: Int
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int
    let macros: [MacroMetric]

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                MacroCalorieRing(
                    proteinGrams: proteinGrams,
                    carbsGrams: carbsGrams,
                    fatGrams: fatGrams
                )
                .frame(width: 96, height: 96)

                VStack(spacing: 0) {
                    Text("\(calories)")
                        .font(.custom("Georgia", size: 28))
                        .fontWeight(.bold)
                    Text("kcal")
                        .font(.custom("Georgia", size: 14))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                ForEach(macros) { macro in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(macro.color)
                            .frame(width: 8, height: 8)

                        Text(macro.name)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(macro.amount)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
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

#Preview {
    let sampleMacros = [
        MacroMetric(name: "Protein", amount: "24g", color: .blue),
        MacroMetric(name: "Carbs", amount: "45g", color: .orange),
        MacroMetric(name: "Fat", amount: "11g", color: .purple),
    ]

    NutritionIndicatorView(
        calories: 375,
        proteinGrams: 24,
        carbsGrams: 45,
        fatGrams: 11,
        macros: sampleMacros
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
