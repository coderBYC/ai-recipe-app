import SwiftUI
import SwiftData
import UIKit
import Foundation
import RevenueCatUI

/// Paste link flow: submit URL → row on Imports tab (`Processing`) → background analyze → `Ready` with approve/delete.
struct PasteLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("settings.language") private var languageSetting: String = "System"
    @AppStorage("settings.subscriptionTier") private var subscriptionTier = "Free"

    var prefillURL: String?
    var autoProcessOnAppear: Bool = false
    /// Parent clears its sheet binding (e.g. `addSheet = nil`) so the Imports tab is reachable.
    var onQueuedToImports: () -> Void

    @State private var linkText = ""
    @State private var errorMessage: String?
    @State private var didAutoProcess = false
    @State private var showPaywall = false

    private static let freeTierCompletedGenerationsBeforePaywall = 2

    private var trimmedURL: String { linkText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canProcess: Bool { !trimmedURL.isEmpty && URL(string: trimmedURL) != nil }

    private func urlNeedsDownloadedVideo(_ raw: String) -> Bool {
        let u = raw.lowercased()
        if u.contains("tiktok.com") || u.contains("vt.tiktok.com") { return true }
        if u.contains("instagram.com") || u.contains("instagr.am") { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            confirmationDialogBlock
        }
        .presentationBackground(.clear)
        .sheet(isPresented: $showPaywall) {
            RevenueCatUI.PaywallView(displayCloseButton: true)
                .onPurchaseCompleted { _, _ in
                    Task { @MainActor in
                        await refreshSubscriptionAndRetryShareExtensionImportIfNeeded()
                    }
                }
                .onRestoreCompleted { _ in
                    Task { @MainActor in
                        await refreshSubscriptionAndRetryShareExtensionImportIfNeeded()
                    }
                }
        }
        .onAppear {
            if let url = prefillURL, !url.isEmpty { linkText = url }
            if autoProcessOnAppear, !didAutoProcess {
                didAutoProcess = true
                Task { @MainActor in
                    await Task.yield()
                    processLink()
                }
            }
        }
        .errorPopup(message: $errorMessage)
    }

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
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: 360)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
        )
        .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
    }

    /// After paywall purchase/restore, continue the share-extension auto-import flow if the user is now Pro.
    @MainActor
    private func refreshSubscriptionAndRetryShareExtensionImportIfNeeded() async {
        await SubscriptionManager.shared.refreshAndSyncPlan()
        subscriptionTier = SubscriptionManager.shared.isPremium ? "Pro" : "Free"
        guard SubscriptionManager.shared.isPremium else { return }
        guard autoProcessOnAppear, canProcess else { return }
        processLink()
    }

    private func currentLanguageCode() -> String {
        switch languageSetting {
        case "Mandarin": return "zh"
        case "Spanish": return "es"
        case "Hindi": return "hi"
        case "Korean": return "ko"
        case "System": return "en"
        default: return "en"
        }
    }

    private func processLink() {
        guard canProcess else { return }
        errorMessage = nil

        Task { @MainActor in
            guard await SupabaseService.shared.currentUserIdString() != nil else {
                errorMessage = "You need to be signed in to analyze videos."
                return
            }

            await SubscriptionManager.shared.checkStatus()
            if !SubscriptionManager.shared.isPremium {
                do {
                    let used = try await SupabaseService.shared.fetchAIUsageCount()
                    if used >= Self.freeTierCompletedGenerationsBeforePaywall {
                        showPaywall = true
                        return
                    }
                } catch {}
            }

            let submission = RecipeImportSubmission(
                importKind: "link",
                sourceURL: trimmedURL,
                languageCode: currentLanguageCode()
            )
            modelContext.insert(submission)
            try? modelContext.save()

            let container = modelContext.container
            let sid = submission.id

            onQueuedToImports()
            dismiss()
            NotificationCenter.default.post(name: .switchToImportsTab, object: nil)

            Task { @MainActor in
                await RecipeImportProcessor.startLinkJob(submissionId: sid, container: container)
            }
        }
    }
}
