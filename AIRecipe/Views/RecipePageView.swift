import SwiftUI
import SwiftData
import UIKit
struct RecipePageView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("settings.fontScale") private var fontScale: Double = 1.0
    @Bindable var recipe: Recipe
    var onDismiss: () -> Void
    var openEditOnAppear: Bool = false

    @State private var showingEdit = false
    @State private var showingImport = false
    @State private var showCookMode = false
    @State private var showShareSheet = false
    @State private var exportError: String?

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
                        ratingSection
                        if !recipe.sourceURL.isEmpty {
                            openLinkSection
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.callout)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        exportRecipe()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.callout)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showingEdit) {
                RecipeEditView(recipe: recipe, onDismiss: { showingEdit = false })
            }
            .sheet(isPresented: $showingImport) {
                PasteLinkView(prefillURL: recipe.sourceURL) { _ in
                    showingImport = false
                }
            }
            .onAppear {
                if openEditOnAppear { showingEdit = true }
            }
            .fullScreenCover(isPresented: $showCookMode) {
                CookModeView(recipe: recipe)
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [recipe.shareableExportText])
            }
            .alert("Export", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK") { exportError = nil }
            } message: {
                if let err = exportError { Text(err) }
            }
        }
    }

    private func exportRecipe() {
        Task { @MainActor in
            exportError = nil
            do {
                try await SupabaseService.shared.useExportOnce()
                showShareSheet = true
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
    
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(recipe.title.isEmpty ? "Recipe" : recipe.title)
                .appFont(.titleBold)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                showingEdit = true
            } label: {
                Image(systemName: "pencil")
                    .font(.callout)
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius))
                    .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
            }
            Button {
                showingImport = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.callout)
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius))
                    .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }
    
    private var videoSection: some View {
        VideoThumbnailView(
            sourceURL: recipe.sourceURL,
            customImageData: recipe.customImageData,
            downloadedVideoURL: recipe.downloadedVideoURL,
            source: recipe.sourceEnum
        )
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
            Text("Estimated time: \(recipe.estimatedCookingMinutes) min")
                .appFont(.callout)
                .foregroundStyle(AppTheme.textPrimary)
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
            Button {
                toggleCheckmark(at: index, linesCount: linesCount)
            } label: {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? AppTheme.triedBadge : AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            Text(line)
                .appFont(.callout)
                .foregroundStyle(checked ? AppTheme.textSecondary : AppTheme.textPrimary)
                .strikethrough(checked)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
    
    private func toggleCheckmark(at index: Int, linesCount: Int) {
        var parts = recipe.ingredientCheckmarks.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        while parts.count < linesCount { parts.append("0") }
        if index < parts.count {
            parts[index] = recipe.ingredientChecked(at: index) ? "0" : "1"
        }
        recipe.ingredientCheckmarks = parts.joined(separator: ",")
    }
    
    /// Steps: vertical circle-line timeline (1 — 2 — 3)
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack{
                Label("Steps", systemImage: "list.number")
                    .appFont(.headlineBold)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            }
            .padding(.vertical,0)
            
            let steps = recipe.stepLines
            if steps.isEmpty {
                Text("No steps listed")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                        stepRow(number: index + 1, text: text)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: 3, height: 24)
                                .padding(.leading, 15)
                        }
                    }
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
        .onTapGesture {
            showCookMode = true
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .appFont(.headlineBold)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.black, in: Circle())
            Text(text)
                .appFont(.callout)
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
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
                        .onTapGesture {
                            if recipe.rating == star {
                                recipe.rating = 0
                                recipe.triedBefore = false
                            } else {
                                recipe.rating = star
                                recipe.triedBefore = true
                            }
                        }
                }
            }
        }
        .padding(14)
        .boxStyle(cornerRadius: AppTheme.boxCornerRadius)
    }
    
    private var openLinkSection: some View {
        Link(destination: URL(string: recipe.sourceURL) ?? URL(string: "https://")!) {
            HStack {
                Text("Open in \(recipe.sourceEnum.rawValue)")
                    .appFont(.headlineBold)
                    .foregroundStyle(.black)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
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

// MARK: - Share sheet (wraps UIActivityViewController; triggers useExportOnce in caller)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Recipe.self, configurations: config)
    let ctx = ModelContext(container)
    let recipe = Recipe(
        title: "Sample Recipe",
        creator: "Chef",
        ingredients: "Salt\nPepper\nOlive oil",
        stepsContent: "Step 1: Mix Mix Mix Mix Mix Mix Mix Mix Mix Mix Mix MixMix Mix Mix Mix Mix MixMix Mix Mix Mix Mix Mix Mix Mix Mix Mix Mix MixMix Mix Mix Mix Mix Mix Mix Mix Mix Mix Mix Mix  \nStep 2: Bake"
    )
    ctx.insert(recipe)
    try! ctx.save()
    return RecipePageView(recipe: recipe, onDismiss: {})
        .modelContainer(container)
}
