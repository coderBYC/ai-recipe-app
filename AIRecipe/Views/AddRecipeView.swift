import SwiftUI
import SwiftData

struct AddRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var title = ""
    @State private var source: RecipeSource = .youtube
    @State private var sourceURL = ""
    @State private var creator = ""
    @State private var timestamp = ""
    @State private var ingredients = ""
    @State private var estimatedCookingMinutes = ""
    @State private var totalSteps = ""
    @State private var stepsContent = ""
    @State private var triedBefore = false
    @State private var notes = ""
    
    private var cookingMinutesInt: Int { Int(estimatedCookingMinutes) ?? 0 }
    private var totalStepsInt: Int { Int(totalSteps) ?? 0 }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section("Title") {
                            TextField("e.g. Viral feta pasta", text: $title)
                                .textFieldStyle(.plain)
                                .appFont(.body)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Source") {
                            Picker("Platform", selection: $source) {
                                ForEach(RecipeSource.allCases) { s in
                                    Label {
                                        Text(s.rawValue)
                                    } icon: {
                                        SourceIconView(source: s)
                                    }
                                    .tag(s)
                                }
                            }
                            .pickerStyle(.segmented)
                            TextField("Paste video URL", text: $sourceURL)
                                .textFieldStyle(.plain)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .appFont(.body)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Creator") {
                            TextField("Channel or creator name", text: $creator)
                                .textFieldStyle(.plain)
                                .appFont(.body)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Timestamp") {
                            TextField("e.g. 2:30 or 0:45", text: $timestamp)
                                .textFieldStyle(.plain)
                                .appFont(.body)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Ingredients") {
                            TextEditor(text: $ingredients)
                                .appFont(.body)
                                .frame(minHeight: 96)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Estimated cooking time (minutes)") {
                            TextField("e.g. 30", text: $estimatedCookingMinutes)
                                .textFieldStyle(.plain)
                                .keyboardType(.numberPad)
                                .appFont(.body)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Total steps") {
                            TextField("e.g. 6", text: $totalSteps)
                                .textFieldStyle(.plain)
                                .keyboardType(.numberPad)
                                .appFont(.body)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Steps (one per line)") {
                            TextEditor(text: $stepsContent)
                                .appFont(.body)
                                .frame(minHeight: 72)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Tried before?") {
                            Toggle(isOn: $triedBefore) {
                                Text("I've already made this recipe")
                                    .appFont(.callout)
                            }
                            .tint(AppTheme.primary)
                        }
                        section("Notes (optional)") {
                            TextEditor(text: $notes)
                                .appFont(.body)
                                .frame(minHeight: 72)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("New Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRecipe() }
                        .appFont(.headlineBold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
    }
    
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(.headlineBold)
                .foregroundStyle(AppTheme.textSecondary)
            content()
        }
    }
    
    private func saveRecipe() {
        let recipe = Recipe(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source,
            sourceURL: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines),
            creator: creator.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: timestamp.trimmingCharacters(in: .whitespacesAndNewlines),
            ingredients: ingredients.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedCookingMinutes: cookingMinutesInt,
            totalSteps: totalStepsInt,
            triedBefore: triedBefore,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            stepsContent: stepsContent.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(recipe)
        dismiss()
    }
}

#Preview {
    AddRecipeView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
