import SwiftUI
import SwiftData

/// Edit Page: HStack header (X, "Edit", check), then same fields as AddRecipeView.
struct RecipeEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var recipe: Recipe
    var onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.surface
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section("Title") {
                            TextField("Recipe title", text: $recipe.title)
                                .textFieldStyle(.plain)
                                .appFont(.body)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Source") {
                            TextField("Video URL", text: $recipe.sourceURL)
                                .textFieldStyle(.plain)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .appFont(.body)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Creator") {
                            TextField("Channel or creator", text: $recipe.creator)
                                .textFieldStyle(.plain)
                                .appFont(.body)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Ingredients") {
                            TextEditor(text: $recipe.ingredients)
                                .appFont(.body)
                                .frame(minHeight: 96)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Estimated cooking time (min)") {
                            TextField("0", value: $recipe.estimatedCookingMinutes, format: .number)
                                .textFieldStyle(.plain)
                                .keyboardType(.numberPad)
                                .appFont(.body)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Total steps") {
                            TextField("0", value: $recipe.totalSteps, format: .number)
                                .textFieldStyle(.plain)
                                .keyboardType(.numberPad)
                                .appFont(.body)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Steps (one per line)") {
                            TextEditor(text: $recipe.stepsContent)
                                .appFont(.body)
                                .frame(minHeight: 72)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        }
                        section("Notes") {
                            TextEditor(text: $recipe.notes)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onDismiss()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.callout)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Edit")
                        .appFont(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onDismiss()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.callout)
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    }
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
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Recipe.self, configurations: config)
    let ctx = ModelContext(container)
    let recipe = Recipe(title: "Edit me", creator: "Chef", ingredients: "Flour", stepsContent: "Mix")
    ctx.insert(recipe)
    try! ctx.save()
    return RecipeEditView(recipe: recipe, onDismiss: {})
        .modelContainer(container)
}
