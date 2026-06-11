import SwiftData
import SwiftUI

/// Shopping list built from unchecked ingredients across the user’s recipes, plus manual items.
struct GroceryListView: View {
    let filterOwnerId: String
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]
    @State private var showAddItemSheet = false
    @State private var manualItems: [ManualGroceryItem] = []
    @State private var mergedItems: [ManualGroceryItem] = []
    @State private var isShowingMerged = false
    @State private var isMerging = false
    @State private var mergeError: String?

    init(filterOwnerId: String) {
        self.filterOwnerId = filterOwnerId
        let oid = filterOwnerId
        _recipes = Query(
            filter: #Predicate<Recipe> { r in
                r.deletedAt == nil && r.ownerUserId == oid
            },
            sort: \Recipe.title
        )
    }

    private struct RecipeGrocerySection: Identifiable {
        let recipe: Recipe
        let items: [(index: Int, line: String)]

        var id: String { recipe.id }
    }

    private var sections: [RecipeGrocerySection] {
        recipes.compactMap { recipe in
            let lines = recipe.ingredientLines
            let unchecked = lines.enumerated().compactMap { index, line -> (Int, String)? in
                recipe.ingredientChecked(at: index) ? nil : (index, line)
            }
            guard !unchecked.isEmpty else { return nil }
            return RecipeGrocerySection(recipe: recipe, items: unchecked)
        }
    }

    private var uncheckedManualItems: [ManualGroceryItem] {
        manualItems.filter { !$0.isChecked }
    }

    private var uncheckedMergedItems: [ManualGroceryItem] {
        mergedItems.filter { !$0.isChecked }
    }

    private var totalUncheckedCount: Int {
        if isShowingMerged { return uncheckedMergedItems.count }
        return sections.reduce(0) { $0 + $1.items.count } + uncheckedManualItems.count
    }

    private var canMerge: Bool {
        !isMerging && (sections.reduce(0) { $0 + $1.items.count } + uncheckedManualItems.count) > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if totalUncheckedCount == 0 && !isMerging {
                        emptyState
                    } else {
                        listContent
                    }
                }
                .background(AppTheme.surface.ignoresSafeArea())

                if isMerging {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Merging list…")
                        .padding(20)
                        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Grocery")
                        .nanumAppFont(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await runMerge() }
                    } label: {
                        Image(systemName: "wand.and.sparkles.inverse")
                            .appFont(.callout)
                            .foregroundStyle(canMerge ? AppTheme.textPrimary : AppTheme.textSecondary)
                        Text("Merge Recipe")
                            .nanumAppFont(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(canMerge ? AppTheme.primary : AppTheme.textSecondary)
                    }
                    .disabled(!canMerge)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddItemSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(AppTheme.bitterFont(size: 18, weight: .regular))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .accessibilityLabel("Add item")
                }
            }
            .sheet(isPresented: $showAddItemSheet) {
                AddGroceryItemSheet { name, unit in
                    addManualItem(name: name, unit: unit)
                }
            }
            .alert("Could not merge", isPresented: Binding(
                get: { mergeError != nil },
                set: { if !$0 { mergeError = nil } }
            )) {
                Button("OK", role: .cancel) { mergeError = nil }
            } message: {
                Text(mergeError ?? "")
            }
            .onAppear { reloadStoredItems() }
            .onChange(of: filterOwnerId) { _, _ in reloadStoredItems() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cart.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.primary.opacity(0.85))
            Text("Your list is empty")
                .appFont(.title3)
                .foregroundStyle(AppTheme.textPrimary)
            Text(isShowingMerged
                 ? "All merged items are checked off."
                 : "Unchecked ingredients from your recipes appear here, or tap + to add your own.")
                .appFont(.callout)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if isShowingMerged {
                Button("Show by recipe") {
                    clearMergedView()
                }
                .appFont(.callout)
                .foregroundStyle(AppTheme.primary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if totalUncheckedCount > 0 {
                    Text("\(totalUncheckedCount) item\(totalUncheckedCount == 1 ? "" : "s") to buy")
                        .appFont(.callout)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 16)
                }

                if isShowingMerged {
                    mergedListSection
                } else {
                    if !uncheckedManualItems.isEmpty {
                        manualSection
                    }
                    ForEach(sections) { section in
                        recipeSection(section)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    private var mergedListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(uncheckedMergedItems) { item in
                IngredientCheckRow(
                    name: item.name,
                    amount: item.unit,
                    checked: item.isChecked
                ) {
                    toggleMergedItem(id: item.id)
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
        .padding(.horizontal, 16)
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Added items")
                .appFont(.headlineBold)
                .foregroundStyle(AppTheme.textSecondary)

            ForEach(uncheckedManualItems) { item in
                IngredientCheckRow(
                    name: item.name,
                    amount: item.unit,
                    checked: item.isChecked
                ) {
                    toggleManualItem(id: item.id)
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
        .padding(.horizontal, 16)
    }

    private func recipeSection(_ section: RecipeGrocerySection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.recipe.title.isEmpty ? "Recipe" : section.recipe.title)
                .appFont(.headlineBold)
                .foregroundStyle(AppTheme.textSecondary)

            let linesCount = section.recipe.ingredientLines.count
            ForEach(section.items, id: \.index) { item in
                IngredientCheckRow(
                    line: item.line,
                    checked: section.recipe.ingredientChecked(at: item.index)
                ) {
                    toggleIngredient(recipe: section.recipe, at: item.index, linesCount: linesCount)
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
        .padding(.horizontal, 16)
    }

    private func reloadStoredItems() {
        guard !filterOwnerId.isEmpty else {
            manualItems = []
            mergedItems = []
            isShowingMerged = false
            return
        }
        manualItems = GroceryManualStore.load(ownerUserId: filterOwnerId)
        isShowingMerged = GroceryManualStore.isShowingMergedView(ownerUserId: filterOwnerId)
        mergedItems = isShowingMerged
            ? GroceryManualStore.loadMerged(ownerUserId: filterOwnerId)
            : []
    }

    private func persistManualItems() {
        guard !filterOwnerId.isEmpty else { return }
        GroceryManualStore.save(manualItems, ownerUserId: filterOwnerId)
    }

    private func persistMergedItems() {
        guard !filterOwnerId.isEmpty else { return }
        GroceryManualStore.saveMerged(mergedItems, ownerUserId: filterOwnerId)
        GroceryManualStore.setShowingMergedView(isShowingMerged, ownerUserId: filterOwnerId)
    }

    private func clearMergedView() {
        isShowingMerged = false
        mergedItems = []
        GroceryManualStore.clearMerged(ownerUserId: filterOwnerId)
    }

    private func addManualItem(name: String, unit: String) {
        let item = ManualGroceryItem(name: name, unit: unit)
        manualItems.append(item)
        persistManualItems()
        if isShowingMerged { clearMergedView() }
    }

    private func toggleManualItem(id: String) {
        guard let index = manualItems.firstIndex(where: { $0.id == id }) else { return }
        manualItems[index].isChecked.toggle()
        persistManualItems()
    }

    private func toggleMergedItem(id: String) {
        guard let index = mergedItems.firstIndex(where: { $0.id == id }) else { return }
        mergedItems[index].isChecked.toggle()
        persistMergedItems()
        if uncheckedMergedItems.isEmpty {
            clearMergedView()
        }
    }

    private func collectMergeInputs() -> [RecipeIngredientItem] {
        var inputs: [RecipeIngredientItem] = []
        for section in sections {
            for item in section.items {
                let parsed = IngredientLine.parse(item.line)
                let name = parsed.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                inputs.append(RecipeIngredientItem(
                    item: name,
                    amount: parsed.amount.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
        for item in uncheckedManualItems {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            inputs.append(RecipeIngredientItem(
                item: name,
                amount: item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return inputs
    }

    @MainActor
    private func runMerge() async {
        let inputs = collectMergeInputs()
        guard !inputs.isEmpty else { return }

        isMerging = true
        mergeError = nil
        defer { isMerging = false }

        do {
            let merged = try await RecipeBackendService.shared.mergeGrocery(ingredients: inputs)
            mergedItems = merged.map { row in
                ManualGroceryItem(
                    name: row.item.trimmingCharacters(in: .whitespacesAndNewlines),
                    unit: row.amount.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }.filter { !$0.name.isEmpty }
            isShowingMerged = true
            persistMergedItems()
        } catch let error as RecipeBackendError {
            switch error {
            case .serverError(let msg): mergeError = msg
            case .network(let err): mergeError = err.localizedDescription
            case .invalidURL: mergeError = "Invalid server URL."
            case .invalidResponse: mergeError = "Invalid server response."
            }
        } catch {
            mergeError = error.localizedDescription
        }
    }

    private func toggleIngredient(recipe: Recipe, at index: Int, linesCount: Int) {
        recipe.toggleIngredientCheck(at: index, linesCount: linesCount)
        recipe.updatedAt = Date()
        try? modelContext.save()
        Task { await SyncService.shared.push(modelContainer: modelContext.container) }
        if isShowingMerged { clearMergedView() }
    }
}

// MARK: - Add grocery item sheet

struct AddGroceryItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (String, String) -> Void

    @State private var itemName = ""
    @State private var unit = ""
    @FocusState private var focusedField: Field?

    private enum Field { case item, unit }

    private var canAdd: Bool {
        !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Item")
                        .appFont(.headlineBold)
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("e.g. Milk", text: $itemName)
                        .textFieldStyle(.plain)
                        .appFont(.body)
                        .padding(14)
                        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        .focused($focusedField, equals: .item)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .unit }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Unit")
                        .appFont(.headlineBold)
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("e.g. 1 gallon", text: $unit)
                        .textFieldStyle(.plain)
                        .appFont(.body)
                        .padding(14)
                        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
                        .focused($focusedField, equals: .unit)
                        .submitLabel(.done)
                        .onSubmit { addIfPossible() }
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .appFont(.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addIfPossible() }
                        .appFont(.body)
                        .fontWeight(.semibold)
                        .disabled(!canAdd)
                }
                ToolbarItem(placement: .principal) {
                    Text("Add item")
                        .nanumAppFont(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .onAppear { focusedField = .item }
        }
        .presentationDetents([.medium])
    }

    private func addIfPossible() {
        let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let amount = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        onAdd(name, amount)
        dismiss()
    }
}

/// Minus / value / plus control (cook time edit, ingredient servings).
struct ServingStepperControl: View {
    @Binding var value: Int
    var minValue: Int = 1
    var maxValue: Int = 99
    var suffix: String = "serving"

    var body: some View {
        HStack(spacing: 8) {
            Button {
                value = max(minValue, value - 1)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .appFont(.title3)
                    .foregroundStyle(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .disabled(value <= minValue)

            HStack(spacing: 1) {
                Text("\(value)")
                    .appFont(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
                Spacer()
                    .frame(width: 6)
                Text(value == 1 ? suffix : "\(suffix)s")
                    .nanumAppFont(.custom(size: 17, weight: .regular))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(minWidth: 44)

            Button {
                value = min(maxValue, value + 1)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .appFont(.title3)
                    .foregroundStyle(.green.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(value >= maxValue)
        }
    }
}

/// Shared ingredient row with circle checkmark (recipe page + grocery list).
struct IngredientCheckRow: View {
    let name: String
    let amount: String
    let checked: Bool
    let onToggle: () -> Void

    init(line: String, checked: Bool, onToggle: @escaping () -> Void) {
        let parsed = IngredientLine.parse(line)
        self.name = parsed.name
        self.amount = parsed.amount
        self.checked = checked
        self.onToggle = onToggle
    }

    init(name: String, amount: String, checked: Bool, onToggle: @escaping () -> Void) {
        self.name = name
        self.amount = amount
        self.checked = checked
        self.onToggle = onToggle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .appFont(.title3)
                    .foregroundStyle(checked ? AppTheme.triedBadge : AppTheme.textSecondary)
            }
            .buttonStyle(.plain)

            Text(name)
                .appFont(.callout)
                .foregroundStyle(checked ? AppTheme.textSecondary : AppTheme.textPrimary)
                .strikethrough(checked)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !amount.isEmpty {
                Text(amount)
                    .appFont(.callout)
                    .foregroundStyle(checked ? AppTheme.textSecondary : AppTheme.textPrimary)
                    .strikethrough(checked)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
