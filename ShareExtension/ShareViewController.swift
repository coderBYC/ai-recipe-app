//
//  ShareViewController.swift
//  ShareExtension
//

import UIKit
import UniformTypeIdentifiers

private enum ShareHandoffConstants {
    static let appGroupSuite = "group.com.airecipe.app"
    static let pendingURLKey = "pendingSharedRecipeURL"
    /// Must match `PendingRecipeImport.presentationModeKey` in the main app.
    static let presentationModeKey = "pendingSharedRecipePresentationMode"
    /// Must match `PendingRecipeImport.silentImportQueueKey` in the main app.
    static let silentImportQueueKey = "silentSharedImportURLQueue"
}

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let cardView = UIView()
    private let statusLabel = UILabel()
    private let loadingSpinner = UIActivityIndicatorView(style: .medium)
    private let openAppButton = UIButton(type: .custom)
    private let closeExtensionButton = UIButton(type: .custom)
    private let errorDismissButton = UIButton(type: .system)
    private var fakeSuccessWorkItem: DispatchWorkItem?

    private var sharedURLString: String?
    private let urlLock = NSLock()

    override func viewDidLoad() {
        super.viewDidLoad()
        if let sheet = self.sheetPresentationController {
                // Defines the heights it can stop at (medium is roughly half the screen)
                sheet.detents = [.medium()]
                
                // Optional: Allows users to see and scroll the app behind it
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                
                // Optional: Shows a small grabber bar at the top of the sheet
                sheet.prefersGrabberVisible = true
            }
        view.backgroundColor = UIColor(white: 0.96, alpha: 1)
        

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .white
        cardView.layer.cornerRadius = 10
        cardView.layer.borderWidth = 2
        cardView.layer.borderColor = UIColor.black.cgColor
        // Neobrutalist offset shadow (block behind)
        let shadow = UIView()
        shadow.translatesAutoresizingMaskIntoConstraints = false
        shadow.backgroundColor = .black
        shadow.layer.cornerRadius = 10
        view.addSubview(shadow)
        view.addSubview(cardView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = ShareExtensionFonts.bitter(size: 15, weight: .semibold)
        statusLabel.textColor = .black
        statusLabel.text = "Grabbing your link…"

        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        loadingSpinner.hidesWhenStopped = true

        openAppButton.translatesAutoresizingMaskIntoConstraints = false
        openAppButton.setTitle("View Import Progress In App", for: .normal)
        openAppButton.titleLabel?.font = ShareExtensionFonts.bitter(size: 16, weight: .heavy)
        openAppButton.titleLabel?.adjustsFontSizeToFitWidth = true
        openAppButton.titleLabel?.minimumScaleFactor = 0.7
        openAppButton.titleLabel?.numberOfLines = 2
        openAppButton.titleLabel?.textAlignment = .center
        openAppButton.backgroundColor = .black
        openAppButton.setTitleColor(.white, for: .normal)
        openAppButton.layer.cornerRadius = 8
        openAppButton.layer.borderWidth = 2
        openAppButton.layer.borderColor = UIColor.black.cgColor
        openAppButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        openAppButton.isHidden = true
        openAppButton.addAction(UIAction { [weak self] _ in
            self?.forceOpenHostApp()
        }, for: .touchUpInside)

        closeExtensionButton.translatesAutoresizingMaskIntoConstraints = false
        closeExtensionButton.setTitle("Close", for: .normal)
        closeExtensionButton.titleLabel?.font = ShareExtensionFonts.bitter(size: 16, weight: .semibold)
        closeExtensionButton.backgroundColor = .white
        closeExtensionButton.setTitleColor(.black, for: .normal)
        closeExtensionButton.layer.cornerRadius = 8
        closeExtensionButton.layer.borderWidth = 2
        closeExtensionButton.layer.borderColor = UIColor.black.cgColor
        closeExtensionButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        closeExtensionButton.isHidden = true
        closeExtensionButton.addAction(UIAction { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }, for: .touchUpInside)

        errorDismissButton.translatesAutoresizingMaskIntoConstraints = false
        errorDismissButton.setTitle("Dismiss", for: .normal)
        errorDismissButton.titleLabel?.font = ShareExtensionFonts.bitter(size: 17, weight: .semibold)
        errorDismissButton.isHidden = true
        errorDismissButton.addAction(UIAction { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }, for: .touchUpInside)

        let innerStack = UIStackView(arrangedSubviews: [statusLabel, loadingSpinner, openAppButton, closeExtensionButton, errorDismissButton])
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        innerStack.axis = .vertical
        innerStack.spacing = 18
        innerStack.alignment = .fill
        cardView.addSubview(innerStack)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            shadow.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 5),
            shadow.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 5),
            shadow.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: 5),
            shadow.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 5),

            innerStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 22),
            innerStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            innerStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            innerStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -22),

            loadingSpinner.heightAnchor.constraint(equalToConstant: 28),
        ])

        loadingSpinner.startAnimating()
        loadSharedURL()
    }
    
    

    deinit {
        fakeSuccessWorkItem?.cancel()
    }

    private func appendToSilentImportQueue(_ raw: String) {
        let suite = UserDefaults(suiteName: ShareHandoffConstants.appGroupSuite)
        let key = ShareHandoffConstants.silentImportQueueKey
        var arr = (suite?.array(forKey: key) as? [String]) ?? []
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !arr.contains(t) { arr.append(t) }
        suite?.set(arr, forKey: key)
    }

    private func removeFromSilentImportQueue(_ raw: String) {
        let suite = UserDefaults(suiteName: ShareHandoffConstants.appGroupSuite)
        let key = ShareHandoffConstants.silentImportQueueKey
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var arr = (suite?.array(forKey: key) as? [String]) ?? []
        arr.removeAll { $0.trimmingCharacters(in: .whitespacesAndNewlines) == t }
        if arr.isEmpty {
            suite?.removeObject(forKey: key)
        } else {
            suite?.set(arr, forKey: key)
        }
    }

    // MARK: - Host app handoff

    /// Safari proves `airecipe://` is registered; inside the extension the **reliable** API is
    /// `extensionContext.open`. The responder chain rarely reaches `UIApplication` here—don’t rely on it first.
    private func forceOpenHostApp() {
        guard let raw = sharedURLString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        removeFromSilentImportQueue(raw)
        UserDefaults(suiteName: ShareHandoffConstants.appGroupSuite)?
            .set("sheet", forKey: ShareHandoffConstants.presentationModeKey)
        persistToAppGroup(raw)

        guard let ctx = extensionContext else {
            showHandoffFailed()
            return
        }

        let candidates: [URL] = [
            "airecipe://import",
            "airecipe://import/",
            "airecipe://open",
        ].compactMap { URL(string: $0) }
        let long = Self.makeImportDeepLink(sharedURL: raw)

        func completeAfterSuccessfulOpen() {
            // Let the system start the app switch before dissolving the extension UI.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }

        func tryExtensionOpen(index: Int) {
            let urls: [URL] = candidates + (long.map { [$0] } ?? [])
            guard index < urls.count else {
                tryUIApplicationOpen(url: URL(string: "airecipe://import")!, completeAfterSuccessfulOpen: completeAfterSuccessfulOpen)
                return
            }
            let u = urls[index]
            ctx.open(u) { ok in
                DispatchQueue.main.async {
                    if ok {
                        completeAfterSuccessfulOpen()
                    } else {
                        tryExtensionOpen(index: index + 1)
                    }
                }
            }
        }

        tryExtensionOpen(index: 0)
    }

    private func tryUIApplicationOpen(url: URL, completeAfterSuccessfulOpen: @escaping () -> Void) {
        var responder: UIResponder? = self
        while let cur = responder {
            if let app = cur as? UIApplication {
                app.open(url, options: [:]) { ok in
                    DispatchQueue.main.async { [weak self] in
                        if ok {
                            completeAfterSuccessfulOpen()
                        } else {
                            let openSel = NSSelectorFromString("openURL:")
                            if app.responds(to: openSel) {
                                app.perform(openSel, with: url)
                                completeAfterSuccessfulOpen()
                            } else {
                                self?.showHandoffFailed()
                            }
                        }
                    }
                }
                return
            }
            responder = cur.next
        }
        showHandoffFailed()
    }

    private func showHandoffFailed() {
        fakeSuccessWorkItem?.cancel()
        fakeSuccessWorkItem = nil
        loadingSpinner.stopAnimating()
        statusLabel.text = "Couldn’t switch apps automatically. Your link is saved — open AI Recipe from the Home screen (or try again)."
        openAppButton.isHidden = true
        closeExtensionButton.isHidden = true
        errorDismissButton.isHidden = false
    }

    private static func makeImportDeepLink(sharedURL: String) -> URL? {
        var c = URLComponents()
        c.scheme = "airecipe"
        c.host = "import"
        c.queryItems = [URLQueryItem(name: "url", value: sharedURL)]
        return c.url
    }

    // MARK: - URL extraction

    private func loadSharedURL() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem], !items.isEmpty else {
            showFailure("Nothing to share. Try sharing a link (not only a video file).")
            return
        }

        let group = DispatchGroup()
        for item in items {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                loadURLFromProvider(provider, group: group)
                loadTextFromProvider(provider, group: group)
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.finalizeExtractedURL()
        }
    }

    private func loadURLFromProvider(_ provider: NSItemProvider, group: DispatchGroup) {
        let typeId = UTType.url.identifier
        guard provider.hasItemConformingToTypeIdentifier(typeId) else { return }

        group.enter()
        provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] item, _ in
            defer { group.leave() }
            guard let self else { return }

            if let url = item as? URL {
                self.setFoundURLIfEmpty(url.absoluteString)
                return
            }
            if let data = item as? Data, let str = String(data: data, encoding: .utf8),
               let u = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                self.setFoundURLIfEmpty(u.absoluteString)
                return
            }
            if let str = item as? String, let u = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                self.setFoundURLIfEmpty(u.absoluteString)
            }
        }
    }

    private func loadTextFromProvider(_ provider: NSItemProvider, group: DispatchGroup) {
        for typeId in [UTType.plainText.identifier, UTType.text.identifier, UTType.utf8PlainText.identifier] {
            guard provider.hasItemConformingToTypeIdentifier(typeId) else { continue }

            group.enter()
            provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] item, _ in
                defer { group.leave() }
                guard let self, let text = item as? String else { return }
                if let extracted = Self.firstURL(in: text) {
                    self.setFoundURLIfEmpty(extracted)
                }
            }
            break
        }
    }

    private func setFoundURLIfEmpty(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        urlLock.lock()
        if sharedURLString == nil {
            sharedURLString = trimmed
        }
        urlLock.unlock()
    }

    private func finalizeExtractedURL() {
        guard let candidate = sharedURLString?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty else {
            showFailure("No link found. Use “Copy link” in the app, then share the URL.")
            return
        }
        guard Self.isSupportedSocialURL(candidate) else {
            showFailure("Only Instagram, YouTube, and TikTok links are supported.")
            return
        }
        sharedURLString = candidate
        appendToSilentImportQueue(candidate)

        loadingSpinner.startAnimating()
        statusLabel.text = "Sending Recipe to Let Him Cook ..."
        openAppButton.isHidden = true
        closeExtensionButton.isHidden = true

        fakeSuccessWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.loadingSpinner.stopAnimating()
            self.statusLabel.text = "Import Successful!"
            self.openAppButton.isHidden = false
            self.closeExtensionButton.isHidden = false
        }
        fakeSuccessWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func persistToAppGroup(_ raw: String) {
        UserDefaults(suiteName: ShareHandoffConstants.appGroupSuite)?.set(raw, forKey: ShareHandoffConstants.pendingURLKey)
    }

    private func showFailure(_ message: String) {
        fakeSuccessWorkItem?.cancel()
        fakeSuccessWorkItem = nil
        loadingSpinner.stopAnimating()
        statusLabel.text = message
        openAppButton.isHidden = true
        closeExtensionButton.isHidden = true
        errorDismissButton.isHidden = false
    }

    private static func isSupportedSocialURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased()
        else { return false }
        return host.contains("instagram.com")
            || host.contains("instagr.am")
            || host.contains("youtube.com")
            || host.contains("youtu.be")
            || host.contains("tiktok.com")
    }

    private static func firstURL(in text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(location: 0, length: (text as NSString).length)
        let match = detector?.firstMatch(in: text, options: [], range: range)
        return match?.url?.absoluteString
    }
}
