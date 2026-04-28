import SwiftUI
import SwiftData
import UIKit

private struct EditableLine: Identifiable, Equatable {
    var id: UUID
    var text: String
    var isFieldEditing: Bool

    init(id: UUID = UUID(), text: String, isFieldEditing: Bool = false) {
        self.id = id
        self.text = text
        self.isFieldEditing = isFieldEditing
    }
}

/// Same layout and controls as `RecipeEditView`, but inserts a new `Recipe` on save.
struct AddRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var draftTitle = ""
    @State private var draftSourceURL = ""
    @State private var draftCreator = ""
    @State private var draftNotes = ""
    @State private var draftPrepMinutes = 0
    @State private var draftCookMinutes = 0

    @State private var ingredientLines: [EditableLine] = [EditableLine(text: "")]
    @State private var stepLines: [EditableLine] = [EditableLine(text: "")]
    @State private var ingredientChecks: [Bool] = [false]

    private enum LineFocus: Hashable {
        case ingredient(UUID)
        case step(UUID)
    }

    @FocusState private var focusedLine: LineFocus?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.surface
                    .ignoresSafeArea()

                List {
                    Section {
                        VStack(alignment: .leading) {
                            Text("Recipe Name")
                                .appFont(.headlineBold)
                                .foregroundStyle(AppTheme.textSecondary)
                            TextField("Recipe title", text: $draftTitle)
                                .textFieldStyle(.plain)
                                .appFont(.body)
                                .padding(12)
                                .boxStyle()
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowBackground(AppTheme.surface)
                                .listRowSeparator(.hidden)
                        }

                        VStack(alignment: .leading) {
                            Text("Link")
                                .appFont(.headlineBold)
                                .foregroundStyle(AppTheme.textSecondary)
                            TextField("Video URL", text: $draftSourceURL)
                                .textFieldStyle(.plain)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .appFont(.body)
                                .padding(12)
                                .boxStyle()
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowBackground(AppTheme.surface)
                                .listRowSeparator(.hidden)
                        }

                        VStack(alignment: .leading) {
                            Text("Creator")
                                .appFont(.headlineBold)
                                .foregroundStyle(AppTheme.textSecondary)
                            TextField("Channel or creator", text: $draftCreator)
                                .textFieldStyle(.plain)
                                .appFont(.body)
                                .padding(12)
                                .boxStyle()
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
                                .listRowBackground(AppTheme.surface)
                                .listRowSeparator(.hidden)
                        }

                        VStack(alignment: .leading) {
                            Text("Total Time")
                                .appFont(.headlineBold)
                                .foregroundStyle(AppTheme.textSecondary)
                            totalTimeBlock
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 5, trailing: 12))
                    .listRowBackground(AppTheme.surface)
                    .listRowSeparator(.hidden)

                    Section {
                        ForEach($ingredientLines) { (line: Binding<EditableLine>) in
                            editableRow(
                                line: line,
                                focusKind: .ingredient(line.wrappedValue.id),
                                onDelete: { deleteIngredient(id: line.wrappedValue.id) },
                                textFieldAxis: .vertical
                            )
                        }
                        .onMove { from, to in
                            ingredientLines.move(fromOffsets: from, toOffset: to)
                            ingredientChecks.move(fromOffsets: from, toOffset: to)
                            normalizeIngredientChecksCount()
                        }

                        addLineButton("Add ingredient", fixedWidth: 220) {
                            ingredientLines.append(EditableLine(text: ""))
                            ingredientChecks.append(false)
                        }
                    } header: {
                        Text("Ingredients")
                            .appFont(.headlineBold)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surface)

                    Section {
                        ForEach($stepLines) { (line: Binding<EditableLine>) in
                            editableRow(
                                line: line,
                                focusKind: .step(line.wrappedValue.id),
                                onDelete: { deleteStep(id: line.wrappedValue.id) },
                                textFieldAxis: .vertical
                            )
                        }
                        .onMove { from, to in
                            stepLines.move(fromOffsets: from, toOffset: to)
                        }

                        addLineButton("Add step", fixedWidth: 180) {
                            stepLines.append(EditableLine(text: ""))
                        }
                    } header: {
                        Text("Steps")
                            .appFont(.headlineBold)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surface)

                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Notes")
                                .appFont(.headlineBold)
                                .foregroundStyle(AppTheme.textSecondary)
                            TextEditor(text: $draftNotes)
                                .appFont(.notes)
                                .foregroundStyle(AppTheme.textPrimary)
                                .frame(minHeight: 72)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .boxStyle()
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(AppTheme.surface)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .environment(\.editMode, .constant(.active))
                .environment(\.defaultMinListRowHeight, 12)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .appFont(.callout)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("New Recipe")
                        .appFont(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        saveRecipe()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .appFont(.callout)
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var totalTimeBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            timeRow(label: "Prep time", value: $draftPrepMinutes)
            timeRow(label: "Cooking time", value: $draftCookMinutes)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowSeparator(.hidden)
        .boxStyle()
    }

    private func timeRow(label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .appFont(.callout)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            HStack(spacing: 10) {
                Button {
                    value.wrappedValue = max(0, value.wrappedValue - 1)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .appFont(.title3)
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue)")
                    .appFont(.title3)
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(minWidth: 36)
                    .monospacedDigit()

                Button {
                    value.wrappedValue = min(999, value.wrappedValue + 1)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .appFont(.title3)
                        .foregroundStyle(.green.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func editableRow(
        line: Binding<EditableLine>,
        focusKind: LineFocus,
        onDelete: @escaping () -> Void,
        textFieldAxis: Axis
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                line.wrappedValue.isFieldEditing.toggle()
                if line.wrappedValue.isFieldEditing {
                    focusedLine = focusKind
                } else if focusedLine == focusKind {
                    focusedLine = nil
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: line.wrappedValue.isFieldEditing ? "pencil.circle.fill" : "pencil.circle")
                    .appFont(.title3)
                    .foregroundStyle(line.wrappedValue.isFieldEditing ? AppTheme.primary : AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Group {
                if line.wrappedValue.isFieldEditing {
                    TextField("", text: textBinding(for: line), axis: textFieldAxis)
                        .textFieldStyle(.plain)
                        .appFont(.body)
                        .lineLimit(textFieldAxis == .vertical ? 1...24 : 1...1)
                        .focused($focusedLine, equals: focusKind)
                } else {
                    Text(line.wrappedValue.text.isEmpty ? " " : line.wrappedValue.text)
                        .appFont(.body)
                        .foregroundStyle(line.wrappedValue.text.isEmpty ? AppTheme.textSecondary.opacity(0.5) : AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .appFont(.title3)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityLabel("Delete line")
        }
        .padding(10)
        .boxStyle()
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(AppTheme.surface)
        .listRowSeparator(.hidden)
    }

    private func textBinding(for line: Binding<EditableLine>) -> Binding<String> {
        Binding(
            get: { line.wrappedValue.text },
            set: { newValue in
                line.wrappedValue.text = newValue
            }
        )
    }

    private func addLineButton(_ title: String, fixedWidth: CGFloat?, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text(title)
            }
            .appFont(.callout)
            .foregroundStyle(AppTheme.primary)
            .frame(maxWidth: fixedWidth == nil ? .infinity : nil, alignment: .leading)
            .padding(10)
            .frame(width: fixedWidth)
            .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(AppTheme.surface)
        .listRowSeparator(.hidden)
    }

    private func deleteIngredient(id: UUID) {
        if focusedLine == .ingredient(id) { focusedLine = nil }
        guard let idx = ingredientLines.firstIndex(where: { $0.id == id }) else { return }
        ingredientLines.remove(at: idx)
        if idx < ingredientChecks.count { ingredientChecks.remove(at: idx) }
        normalizeIngredientChecksCount()
        if ingredientLines.isEmpty { ingredientLines = [EditableLine(text: "")] }
        normalizeIngredientChecksCount()
    }

    private func deleteStep(id: UUID) {
        if focusedLine == .step(id) { focusedLine = nil }
        guard let idx = stepLines.firstIndex(where: { $0.id == id }) else { return }
        stepLines.remove(at: idx)
        if stepLines.isEmpty { stepLines = [EditableLine(text: "")] }
    }

    private func normalizeIngredientChecksCount() {
        while ingredientChecks.count < ingredientLines.count {
            ingredientChecks.append(false)
        }
        while ingredientChecks.count > ingredientLines.count {
            ingredientChecks.removeLast()
        }
    }

    private func saveRecipe() {
        let source = RecipeSource.inferred(from: draftSourceURL.trimmingCharacters(in: .whitespacesAndNewlines))

        var ingOut: [String] = []
        var ingChecksOut: [String] = []
        for (i, line) in ingredientLines.enumerated() {
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            ingOut.append(t)
            let checked = (i < ingredientChecks.count) ? ingredientChecks[i] : false
            ingChecksOut.append(checked ? "1" : "0")
        }

        let nonEmptySteps = stepLines
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let recipe = Recipe(
            title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source,
            sourceURL: draftSourceURL.trimmingCharacters(in: .whitespacesAndNewlines),
            creator: draftCreator.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: "",
            ingredients: ingOut.joined(separator: "\n"),
            estimatedCookingMinutes: draftCookMinutes,
            prepMinutes: draftPrepMinutes,
            totalSteps: nonEmptySteps.count,
            triedBefore: false,
            notes: draftNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            stepsContent: nonEmptySteps.joined(separator: "\n"),
            ingredientCheckmarks: ingChecksOut.joined(separator: ",")
        )
        modelContext.insert(recipe)
        try? modelContext.save()
    }
}

#Preview {
    AddRecipeView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
