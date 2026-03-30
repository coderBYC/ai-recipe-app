//
//  ShareViewController.swift
//  RecipeShareExtension
//
//  Created by Bryan Chen on 2026/3/20.
//

import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
    private let loadingView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let loadingLabel = UILabel()
    private var didAutoSubmit = false
    private var progressTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLoadingOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAutoSubmit else { return }
        didAutoSubmit = true
        handleShareAndOpenApp()
    }

    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        return true
    }

    override func didSelectPost() {
        handleShareAndOpenApp()
    }

    private func handleShareAndOpenApp() {
        setLoading(true)
        Task { @MainActor in
            if let shared = await extractSharedURLString(), let encoded = shared.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                let deepLink = "airecipe://import?url=\(encoded)"
                if let url = URL(string: deepLink) {
                    _ = await openURL(url)
                }
            }
            progressTask?.cancel()
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }

    private func extractSharedURLString() async -> String? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = await loadItem(from: provider, typeIdentifier: UTType.url.identifier),
                   let url = value as? URL {
                    return url.absoluteString
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let value = await loadItem(from: provider, typeIdentifier: UTType.plainText.identifier) {
                    if let text = value as? String, let candidate = firstURL(in: text) {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    private func firstURL(in text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let match = detector?.firstMatch(in: text, options: [], range: range)
        return match?.url?.absoluteString
    }

    private func loadItem(from provider: NSItemProvider, typeIdentifier: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: item as? NSSecureCoding)
            }
        }
    }

    private func setupLoadingOverlay() {
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        loadingView.alpha = 0
        loadingView.layer.cornerRadius = 14
        loadingView.clipsToBounds = true

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.25)
        progressView.progressTintColor = .white
        progressView.progress = 0

        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.text = "Preparing recipe import..."
        loadingLabel.textColor = .white
        loadingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        loadingLabel.textAlignment = .center

        view.addSubview(loadingView)
        loadingView.contentView.addSubview(progressView)
        loadingView.contentView.addSubview(loadingLabel)

        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loadingView.widthAnchor.constraint(equalToConstant: 250),
            loadingView.heightAnchor.constraint(equalToConstant: 120),

            loadingLabel.topAnchor.constraint(equalTo: loadingView.contentView.topAnchor, constant: 26),
            loadingLabel.leadingAnchor.constraint(equalTo: loadingView.contentView.leadingAnchor, constant: 12),
            loadingLabel.trailingAnchor.constraint(equalTo: loadingView.contentView.trailingAnchor, constant: -12),

            progressView.topAnchor.constraint(equalTo: loadingLabel.bottomAnchor, constant: 16),
            progressView.leadingAnchor.constraint(equalTo: loadingView.contentView.leadingAnchor, constant: 18),
            progressView.trailingAnchor.constraint(equalTo: loadingView.contentView.trailingAnchor, constant: -18),
        ])
    }

    private func setLoading(_ loading: Bool) {
        if loading {
            progressView.progress = 0
            progressTask?.cancel()
            progressTask = Task { @MainActor [weak self] in
                guard let self else { return }
                // Indeterminate-like fill animation while we hand off to app.
                while !Task.isCancelled {
                    let next = min(self.progressView.progress + 0.08, 0.9)
                    self.progressView.setProgress(next, animated: true)
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            }
            UIView.animate(withDuration: 0.2) {
                self.loadingView.alpha = 1
            }
            navigationController?.navigationBar.isUserInteractionEnabled = false
            view.isUserInteractionEnabled = false
        } else {
            progressTask?.cancel()
            progressView.setProgress(1.0, animated: true)
            loadingView.alpha = 0
            navigationController?.navigationBar.isUserInteractionEnabled = true
            view.isUserInteractionEnabled = true
        }
    }

    private func openURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            extensionContext?.open(url) { success in
                if success {
                    continuation.resume(returning: true)
                    return
                }
                // Fallback for older behavior.
                let selector = NSSelectorFromString("openURL:")
                var responder: UIResponder? = self
                while responder != nil {
                    if responder?.responds(to: selector) == true {
                        _ = responder?.perform(selector, with: url)
                        continuation.resume(returning: true)
                        return
                    }
                    responder = responder?.next
                }
                continuation.resume(returning: false)
            }
        }
    }
}
