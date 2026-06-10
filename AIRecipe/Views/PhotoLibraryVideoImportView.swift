import AVFoundation
import CoreTransferable
import Foundation
import Photos
import PhotosUI
import RevenueCatUI
import SwiftData
import SwiftUI

private struct PhotoPickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

private enum PhotoImportError: LocalizedError {
    case couldNotReadVideo
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .couldNotReadVideo:
            return "Could not read the selected video. Try another clip or re-save it to Photos."
        case .notSignedIn:
            return "You need to be signed in to analyze videos."
        }
    }
}

/// Picks a video from Photos → row on Imports tab (`Processing`) → background upload + analyze.
struct PhotoLibraryVideoImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("settings.language") private var languageSetting: String = "System"
    @AppStorage("settings.subscriptionTier") private var subscriptionTier = "Free"

    var onQueuedToImports: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var showPaywall = false

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

    var body: some View {
        ZStack {
            Color.black.opacity(0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            importBlock
        }
        .presentationBackground(.clear)
        .sheet(isPresented: $showPaywall) {
            RevenueCatUI.PaywallView(displayCloseButton: true)
                .onPurchaseCompleted { _, _ in
                    Task { @MainActor in
                        await SubscriptionManager.shared.refreshAndSyncPlan()
                        subscriptionTier = SubscriptionManager.shared.isPremium ? "Pro" : "Free"
                    }
                }
                .onRestoreCompleted { _ in
                    Task { @MainActor in
                        await SubscriptionManager.shared.refreshAndSyncPlan()
                        subscriptionTier = SubscriptionManager.shared.isPremium ? "Pro" : "Free"
                    }
                }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await processPickedItem(newItem) }
        }
        .errorPopup(message: $errorMessage)
    }

    private var importBlock: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Video from Photos")
                    .appFont(.title3)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Choose a video — processing happens on the Imports tab.")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            PhotosPicker(selection: $pickerItem, matching: .videos, photoLibrary: .shared()) {
                Label("Choose video", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if let errorMessage {
                Text(errorMessage)
                    .appFont(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Divider().padding(.vertical, 16)

            Button("Cancel") { dismiss() }
                .appFont(.body)
                .foregroundStyle(Color.red)
                .padding(.bottom, 18)
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

    private func processPickedItem(_ item: PhotosPickerItem) async {
        await MainActor.run { errorMessage = nil }

        var tempURL: URL?
        do {
            guard await SupabaseService.shared.currentUserIdString() != nil else {
                throw PhotoImportError.notSignedIn
            }

            await SubscriptionManager.shared.checkStatus()
            let isPremium = await MainActor.run { SubscriptionManager.shared.isPremium }
            if !isPremium {
                do {
                    let used = try await SupabaseService.shared.fetchAIUsageCount()
                    if FreeTierLimits.isImportLimitReached(usedCount: used) {
                        await MainActor.run {
                            pickerItem = nil
                            showPaywall = true
                        }
                        return
                    }
                } catch {}
            }

            let fileURL = try await resolveVideoFileURL(from: item)
            tempURL = fileURL

            let relPath: String
            do {
                relPath = try RecipeImportProcessor.copyVideoForPendingJob(from: fileURL)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
                try? FileManager.default.removeItem(at: fileURL)
                await MainActor.run { pickerItem = nil }
                return
            }

            try? FileManager.default.removeItem(at: fileURL)
            tempURL = nil

            let submission = RecipeImportSubmission(
                importKind: "photo",
                sourceURL: "Video from Photos",
                languageCode: currentLanguageCode(),
                pendingVideoRelPath: relPath
            )
            await MainActor.run {
                modelContext.insert(submission)
                try? modelContext.save()
                modelContext.processPendingChanges()
                let container = modelContext.container
                let sid = submission.id
                onQueuedToImports()
                dismiss()
                NotificationCenter.default.post(name: .switchToImportsTab, object: nil)
                pickerItem = nil
                Task { @MainActor in
                    await RecipeImportProcessor.startPhotoJob(submissionId: sid, container: container)
                }
            }
        } catch let err as PhotoImportError {
            await MainActor.run {
                errorMessage = err.localizedDescription
                pickerItem = nil
            }
            if let tempURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                pickerItem = nil
            }
            if let tempURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
    }

    private func resolveVideoFileURL(from item: PhotosPickerItem) async throws -> URL {
        if let movie = try? await item.loadTransferable(type: PhotoPickedMovie.self) {
            return movie.url
        }
        guard let id = item.itemIdentifier else {
            throw PhotoImportError.couldNotReadVideo
        }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else {
            throw PhotoImportError.couldNotReadVideo
        }
        return try await exportPHVideoAssetToTempFile(asset)
    }

    private func exportPHVideoAssetToTempFile(_ asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let opts = PHVideoRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { av, _, info in
                if let err = info?[PHImageErrorKey] as? Error {
                    cont.resume(throwing: err)
                    return
                }
                guard let av else {
                    cont.resume(throwing: PhotoImportError.couldNotReadVideo)
                    return
                }
                if let urlAsset = av as? AVURLAsset {
                    let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                    do {
                        if FileManager.default.fileExists(atPath: dest.path) {
                            try? FileManager.default.removeItem(at: dest)
                        }
                        try FileManager.default.copyItem(at: urlAsset.url, to: dest)
                        cont.resume(returning: dest)
                    } catch {
                        cont.resume(throwing: error)
                    }
                    return
                }
                cont.resume(throwing: PhotoImportError.couldNotReadVideo)
            }
        }
    }
}
