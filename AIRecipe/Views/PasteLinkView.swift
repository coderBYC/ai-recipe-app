import SwiftUI
import SwiftData
import UIKit
import Foundation

/// Paste link flow presented like a confirmation dialog: title, message, field, then vertical action list.
struct PasteLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("settings.language") private var languageSetting: String = "System"

    var prefillURL: String?
    var autoProcessOnAppear: Bool = false
    var onProcessed: (Recipe) -> Void

    @State private var linkText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var loadingProgress: Double = 0
    @State private var loadingPhase: LoadingPhase = .idle
    @State private var progressTask: Task<Void, Never>?
    @State private var didAutoProcess = false

    private var trimmedURL: String { linkText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canProcess: Bool { !trimmedURL.isEmpty && URL(string: trimmedURL) != nil }

    /// Backend uses download -> Gemini for TikTok and Instagram, and only stores/serves the resulting file for Pro.
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
                .onTapGesture { if !isProcessing { dismiss() } }

            if isProcessing {
                generatingOverlay
            } else {
                confirmationDialogBlock
            }
        }
        .presentationBackground(.clear)
        .onAppear {
            if let url = prefillURL, !url.isEmpty { linkText = url }
            if autoProcessOnAppear, !didAutoProcess {
                didAutoProcess = true
                Task { @MainActor in
                    // Let the sheet appear before triggering backend work.
                    await Task.yield()
                    processLink()
                }
            }
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

    private var generatingOverlay: some View {
        LoadingGenerateOverlay(
            languageCode: currentLanguageCode(),
            phase: loadingPhase,
            progress: loadingProgress
        )
        .ignoresSafeArea()
    }

    private func currentLanguageCode() -> String {
        switch languageSetting {
        case "Mandarin":
            return "zh"
        case "Spanish":
            return "es"
        case "Hindi":
            return "hi"
        case "Korean":
            return "ko"
        case "System":
            return "en"
        default:
            return "en"
        }
    }

    private func processLink() {
        guard canProcess else { return }
        errorMessage = nil
        isProcessing = true
        loadingPhase = .starting
        loadingProgress = 0

        progressTask?.cancel()
        progressTask = Task { @MainActor in
            // Fake but smooth progress until backend returns.
            while !Task.isCancelled {
                let cap = loadingPhase == .done ? 1.0 : 0.92
                if loadingProgress >= cap {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    continue
                }

                // "Apple download" feel: quick bursts + pauses.
                let remaining = cap - loadingProgress
                let burst = min(remaining, Double.random(in: 0.05...0.14))
                let duration = Double.random(in: 0.16...0.32)
                withAnimation(.easeOut(duration: duration)) {
                    loadingProgress = min(cap, loadingProgress + burst)
                }
                let pause = UInt64(Double.random(in: 0.18...0.95) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: pause)
            }
        }

        Task { @MainActor in
            do {
                guard let userId = await SupabaseService.shared.currentUserIdString() else {
                    errorMessage = "You need to be signed in to analyze videos."
                    isProcessing = false
                    progressTask?.cancel()
                    return
                }

                let needsDownloadedVideo = urlNeedsDownloadedVideo(trimmedURL)
                if needsDownloadedVideo {
                    // Make sure RevenueCat entitlement is up-to-date before the backend decides
                    // whether to store/serve the downloaded video (Pro-only preview).
                    loadingPhase = .syncing
                    await SubscriptionManager.shared.checkStatus()
                }

                loadingPhase = .sending
                let response = try await RecipeBackendService.shared.analyzeReel(
                    url: trimmedURL,
                    language: currentLanguageCode(),
                    userId: userId,
                    isPro: needsDownloadedVideo ? SubscriptionManager.shared.isPremium : nil
                )
                loadingPhase = .infoDone
                let recipe = response.toRecipe(sourceURL: trimmedURL, modelContext: modelContext)
                try? modelContext.save()
                loadingPhase = .done
                withAnimation(.easeInOut(duration: 0.2)) { loadingProgress = 1.0 }
                progressTask?.cancel()
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
                progressTask?.cancel()
                isProcessing = false
            } catch RecipeBackendError.serverError(let msg) {
                if msg.contains("AI usage limit reached") || msg.contains("AI usage limit reached or not allowed") || msg.contains("429") {
                    errorMessage = "You've reached your AI usage limit for this period. Upgrade your plan in Settings to continue."
                } else {
                    errorMessage = "Server error: \(msg)"
                }
                progressTask?.cancel()
                isProcessing = false
            } catch {
                errorMessage = error.localizedDescription
                progressTask?.cancel()
                isProcessing = false
            }
        }
    }
}

private enum LoadingPhase: String {
    case idle
    case starting
    case syncing
    case sending
    case infoDone
    case done
}

private struct LoadingGenerateOverlay: View {
    let languageCode: String
    let phase: LoadingPhase
    let progress: Double

    private var infoIsDone: Bool { phase == .infoDone || phase == .done }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    TypingHeadlineText(
                        fullText: "HOL UP\nLET HIM COOK...",
                        phase: phase
                    )

                    Image("LoadingMeme")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    AppleLikeLoadingBar(progress: max(0, min(1, progress)))
                        .frame(maxWidth: 320)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

private struct AppleLikeLoadingBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height: CGFloat = 18
            let clamped = max(0, min(1, progress))
            let filled = max(height, width * clamped) // keep the left end nicely rounded
            let knobX = min(max(height / 2, width * clamped), width - height / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white)
                    .overlay(
                        Capsule().stroke(Color.black.opacity(0.22), lineWidth: 1)
                    )

                Capsule()
                    .fill(Color.black)
                    .frame(width: filled)
            }
            .frame(height: height)
        }
        .frame(height: 18)
    }
}

private struct TypingHeadlineText: View {
    let fullText: String
    let phase: LoadingPhase

    @State private var typedCount: Int = 0
    @State private var didStart = false
    @State private var showCursor = true
    @State private var didStartDotLoop = false

    private var isComplete: Bool { typedCount >= fullText.count }
    private var dotLoopBaseCount: Int {
        // If the string ends with "...", loop those dots while loading.
        fullText.hasSuffix("...") ? max(0, fullText.count - 3) : fullText.count
    }

    var body: some View {
        let prefix = String(fullText.prefix(typedCount))
        let cursor = (!isComplete && showCursor) ? "|" : ""
        Text(prefix + cursor)
            .font(.system(size: 28, weight: .medium, design: .serif))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.black)
            .onAppear {
                guard !didStart else { return }
                didStart = true
                Task { @MainActor in
                    // Cursor blink
                    while !Task.isCancelled && !isComplete {
                        showCursor.toggle()
                        try? await Task.sleep(nanoseconds: 420_000_000)
                    }
                }
                Task { @MainActor in
                    // Typing effect; speed varies a bit.
                    while !Task.isCancelled && typedCount < fullText.count {
                        let ch = fullText[fullText.index(fullText.startIndex, offsetBy: typedCount)]
                        let base: UInt64 = (ch == "\n") ? 120_000_000 : 46_000_000
                        let jitter = UInt64.random(in: 0...50_000_000)
                        typedCount += 1
                        try? await Task.sleep(nanoseconds: base + jitter)
                    }
                    // If we're still generating, keep "typing" the trailing dots loop.
                    while !Task.isCancelled && phase != .done {
                        guard fullText.hasSuffix("...") else {
                            // No dots to loop; just keep cursor blinking until done.
                            showCursor = true
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            continue
                        }
                        showCursor = false
                        typedCount = dotLoopBaseCount
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        typedCount = dotLoopBaseCount + 1
                        try? await Task.sleep(nanoseconds: 160_000_000)
                        typedCount = dotLoopBaseCount + 2
                        try? await Task.sleep(nanoseconds: 160_000_000)
                        typedCount = dotLoopBaseCount + 3
                        try? await Task.sleep(nanoseconds: 520_000_000)
                    }
                    showCursor = false
                }
            }
            .onChange(of: phase) { _, newPhase in
                // If generation finishes before typing ends, jump to full text.
                if newPhase == .done {
                    typedCount = fullText.count
                    showCursor = false
                }
            }
    }
}

