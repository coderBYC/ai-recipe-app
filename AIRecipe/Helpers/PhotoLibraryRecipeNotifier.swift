import Foundation
import Photos
import UIKit
import UserNotifications

// MARK: - Pending open from notification / deep link

enum PendingPhotoRecipeImport {
    static let userDefaultsKey = "pendingOpenPhotoRecipeImport"

    static func markPending() {
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }

    /// Returns and clears whether the user asked to open the photo import flow.
    static func takePending() -> Bool {
        guard UserDefaults.standard.bool(forKey: userDefaultsKey) else { return false }
        UserDefaults.standard.set(false, forKey: userDefaultsKey)
        return true
    }
}

// MARK: - Notification delegate

final class RecipeNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RecipeNotificationCenterDelegate()

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        _ = notification
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.content.categoryIdentifier
        let action = response.notification.request.content.userInfo["action"] as? String
        if id == PhotoLibraryRecipeNotifier.notificationCategoryId || action == "openPhotoImport" {
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier
                || response.actionIdentifier == "OPEN_PHOTO_RECIPE" {
                PendingPhotoRecipeImport.markPending()
                NotificationCenter.default.post(name: .openPhotoRecipeImport, object: nil)
            }
        }
        completionHandler()
    }
}

// MARK: - Recent save detection (on foreground)

final class PhotoLibraryRecipeNotifier {
    static let shared = PhotoLibraryRecipeNotifier()
    static let notificationCategoryId = "photo_recipe_nudge"

    private let notifiedIdsKey = "photoLibraryNotifiedAssetIds"
    private let lastNudgeKey = "photoLibraryLastRecipeNudgeAt"
    private let recentWindow: TimeInterval = 15 * 60
    private let minNudgeGap: TimeInterval = 6 * 3600

    private init() {}

    func registerCategories() {
        let open = UNNotificationAction(
            identifier: "OPEN_PHOTO_RECIPE",
            title: "Open",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryId,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Requests photo library and notification permission when still undetermined (system shows dialogs once).
    func requestNeededPermissionsIfPossible() async {
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// When the app becomes active, look for very recent new videos and nudge the user (local notification or in-app banner).
    func scanForRecentSavedVideosAndNotify() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        let threshold = Date().addingTimeInterval(-recentWindow)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate > %@", threshold as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 25
        let assets = PHAsset.fetchAssets(with: .video, options: options)
        guard assets.count > 0 else { return }

        let notified = Set(UserDefaults.standard.stringArray(forKey: notifiedIdsKey) ?? [])
        var newId: String?
        for i in 0..<assets.count {
            let a = assets.object(at: i)
            if !notified.contains(a.localIdentifier) {
                newId = a.localIdentifier
                break
            }
        }
        guard let assetId = newId else { return }

        if let last = UserDefaults.standard.object(forKey: lastNudgeKey) as? Date,
           Date().timeIntervalSince(last) < minNudgeGap {
            return
        }

        let notifSettings = await UNUserNotificationCenter.current().notificationSettings()
        let canPush = notifSettings.authorizationStatus == .authorized
            || notifSettings.authorizationStatus == .provisional
            || notifSettings.authorizationStatus == .ephemeral

        if canPush {
            let content = UNMutableNotificationContent()
            content.title = "Wanna Build Recipe?"
            content.body = "You recently saved a video to Photos. Open Let Him Cook to pick it and generate a recipe."
            content.sound = .default
            content.categoryIdentifier = Self.notificationCategoryId
            content.userInfo = ["action": "openPhotoImport"]

            let request = UNNotificationRequest(
                identifier: "photo_recipe_nudge_\(assetId)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
            )
            try? await UNUserNotificationCenter.current().add(request)
        } else {
            await MainActor.run {
                NotificationCenter.default.post(name: .savedVideoRecipeSuggestion, object: nil)
            }
        }

        var updated = notified
        updated.insert(assetId)
        UserDefaults.standard.set(Array(updated.suffix(400)), forKey: notifiedIdsKey)
        UserDefaults.standard.set(Date(), forKey: lastNudgeKey)
    }
}
