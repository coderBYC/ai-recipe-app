import SwiftUI
import SwiftData

struct CreateCookbookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let ownerUserId: String
    var onCreated: (Cookbook) -> Void = { _ in }

    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Name your cookbook")
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                TextField("Cookbook name", text: $name)
                    .textFieldStyle(.plain)
                    .appFont(.body)
                    .padding(14)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.boxCornerRadius)
                            .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
                    )
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { createIfPossible() }

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
                    Button("Create") { createIfPossible() }
                        .appFont(.body)
                        .fontWeight(.semibold)
                        .disabled(!canCreate)
                }
                ToolbarItem(placement: .principal) {
                    Text("New Cookbook")
                        .nanumAppFont(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .onAppear {
                nameFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func createIfPossible() {
        guard let book = CookbookService.createCookbook(
            name: name,
            ownerUserId: ownerUserId,
            modelContext: modelContext
        ) else { return }
        onCreated(book)
        dismiss()
    }
}
