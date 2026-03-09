import SwiftUI
import SwiftData

/// Paste link flow presented like a confirmation dialog: title, message, field, then vertical action list.
struct PasteLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("settings.language") private var languageSetting: String = "System"

    var prefillURL: String?
    var onProcessed: (Recipe) -> Void

    @State private var linkText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private var trimmedURL: String { linkText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canProcess: Bool { !trimmedURL.isEmpty && URL(string: trimmedURL) != nil }

    var body: some View {
        ZStack {
            Color.black.opacity(0)
                .ignoresSafeArea()
                .onTapGesture { if !isProcessing { dismiss() } }

            if isProcessing {
                processingBlock
            } else {
                confirmationDialogBlock
            }
        }
        .presentationBackground(.clear)
        .onAppear {
            if let url = prefillURL, !url.isEmpty { linkText = url }
        }
    }

    /// Confirmation-dialog style: title, message, text field, then vertical list of actions with separators.
    private var confirmationDialogBlock: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Add from link")
                    .appFont(.title3)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Paste a YouTube, Instagram, or TikTok link below.")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            TextField("https://...", text: $linkText)
                .textFieldStyle(.plain)
                .keyboardType(.URL)
                .textSelection(.enabled)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .appFont(.body)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
                .padding(.top, 14)

            if let err = errorMessage {
                Text(err)
                    .appFont(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
            }

            VStack(spacing: 0) {
                Rectangle()
                    .fill(AppTheme.textSecondary.opacity(0.2))
                    .frame(height: 1)
                    .padding(.top, 20)

                Button {
                    processLink()
                } label: {
                    Text("Process video")
                        .appFont(.headline)
                        .foregroundStyle(canProcess ? AppTheme.primary : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .disabled(!canProcess)
                .buttonStyle(.plain)

                Rectangle()
                    .fill(AppTheme.textSecondary.opacity(0.2))
                    .frame(height: 1)

                Button {
                    if let str = UIPasteboard.general.string {
                        linkText = str
                        errorMessage = nil
                    }
                } label: {
                    Text("Paste from clipboard")
                        .appFont(.body)
                        .foregroundStyle(AppTheme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(AppTheme.textSecondary.opacity(0.2))
                    .frame(height: 1)

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .appFont(.body)
                        .foregroundStyle(AppTheme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: 280)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: AppTheme.shadow, radius: 20, x: 0, y: 8)
    }

    private var processingBlock: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.0)
                .tint(AppTheme.primary)
            Text("Processing video…")
                .appFont(.headline)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(24)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: AppTheme.shadow, radius: 20, x: 0, y: 8)
    }

    private func currentLanguageCode() -> String {
        switch languageSetting {
        case "Chinese":
            return "zh"
        default:
            return "en"
        }
    }
    private func processLink() {
        guard canProcess else { return }
        errorMessage = nil
        isProcessing = true

        Task { @MainActor in
            do {
                let response = try await RecipeBackendService.shared.analyzeReel(url: trimmedURL, language: currentLanguageCode())
                let recipe = response.toRecipe(sourceURL: trimmedURL, modelContext: modelContext)
                try? modelContext.save()
                isProcessing = false
                await Task.yield()
                dismiss()
                onProcessed(recipe)
            } catch RecipeBackendError.network(let err) {
                let nsErr = err as NSError
                if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCannotConnectToHost {
                    errorMessage = "Cannot connect to the backend. Start it on your Mac."
                } else {
                    errorMessage = "Network error: \(err.localizedDescription)"
                }
                isProcessing = false
            } catch RecipeBackendError.serverError(let msg) {
                errorMessage = "Server error: \(msg)"
                isProcessing = false
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }
}
