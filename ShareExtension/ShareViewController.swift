//
//  ShareViewController.swift
//  ShareExtension
//

import UIKit
import UniformTypeIdentifiers

private enum ShareHandoffConstants {
    static let appGroupSuite = "group.com.airecipe.app"
    static let pendingURLKey = "pendingSharedRecipeURL"
}

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let cardView = UIView()
    private let statusLabel = UILabel()
    private let loadingBar = NeoBrutalistIndeterminateBar()
    private let generateButton = UIButton(type: .custom)
    private let errorDismissButton = UIButton(type: .system)

    private var sharedURLString: String?
    private let urlLock = NSLock()

    override func viewDidLoad() {
        super.viewDidLoad()
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
        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.textColor = .black
        statusLabel.text = "Grabbing your link…"

        loadingBar.translatesAutoresizingMaskIntoConstraints = false

        generateButton.translatesAutoresizingMaskIntoConstraints = false
        generateButton.setTitle("⚡️ GENERATE RECIPE", for: .normal)
        generateButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .heavy)
        generateButton.titleLabel?.adjustsFontSizeToFitWidth = true
        generateButton.titleLabel?.minimumScaleFactor = 0.75
        generateButton.backgroundColor = .black
        generateButton.setTitleColor(.white, for: .normal)
        generateButton.layer.cornerRadius = 8
        generateButton.layer.borderWidth = 2
        generateButton.layer.borderColor = UIColor.black.cgColor
        generateButton.contentEdgeInsets = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        generateButton.isHidden = true
        generateButton.addAction(UIAction { [weak self] _ in
            self?.forceOpenHostApp()
        }, for: .touchUpInside)

        errorDismissButton.translatesAutoresizingMaskIntoConstraints = false
        errorDismissButton.setTitle("Dismiss", for: .normal)
        errorDismissButton.isHidden = true
        errorDismissButton.addAction(UIAction { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }, for: .touchUpInside)

        let innerStack = UIStackView(arrangedSubviews: [statusLabel, loadingBar, generateButton, errorDismissButton])
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

            loadingBar.heightAnchor.constraint(equalToConstant: 22),
        ])

        loadSharedURL()
    }

    // MARK: - Host app handoff

    /// Safari proves `airecipe://` is registered; inside the extension the **reliable** API is
    /// `extensionContext.open`. The responder chain rarely reaches `UIApplication` here—don’t rely on it first.
    private func forceOpenHostApp() {
        guard let raw = sharedURLString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
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
        statusLabel.text = "Couldn’t switch apps automatically. Your link is saved — open AI Recipe from the Home screen (or try again)."
        generateButton.isHidden = true
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
        persistToAppGroup(candidate)

        loadingBar.stopAnimating()
        loadingBar.isHidden = true
        statusLabel.text = "Ready. One tap to cook."
        generateButton.isHidden = false
    }

    private func persistToAppGroup(_ raw: String) {
        UserDefaults(suiteName: ShareHandoffConstants.appGroupSuite)?.set(raw, forKey: ShareHandoffConstants.pendingURLKey)
    }

    private func showFailure(_ message: String) {
        loadingBar.stopAnimating()
        loadingBar.isHidden = true
        statusLabel.text = message
        generateButton.isHidden = true
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

// MARK: - Neobrutalist loading bar

private final class NeoBrutalistIndeterminateBar: UIView {
    private let track = UIView()
    private let fill = UIView()
    private var displayLink: CADisplayLink?
    private var phase: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.translatesAutoresizingMaskIntoConstraints = false
        track.backgroundColor = .white
        track.layer.borderWidth = 2
        track.layer.borderColor = UIColor.black.cgColor
        track.layer.cornerRadius = 11
        track.clipsToBounds = true

        fill.backgroundColor = .black
        fill.layer.cornerRadius = 6

        addSubview(track)
        track.addSubview(fill)
        NSLayoutConstraint.activate([
            track.topAnchor.constraint(equalTo: topAnchor),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        startAnimating()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFillFrame()
    }

    private func startAnimating() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        phase += 0.045
        if phase > 1 { phase -= 1 }
        updateFillFrame()
    }

    private func updateFillFrame() {
        let w = track.bounds.width
        let h = track.bounds.height
        guard w > 0, h > 0 else { return }
        let inset: CGFloat = 5
        let innerW = w - inset * 2
        let pulse = (sin(phase * .pi * 2) + 1) / 2
        let fw = max(28, innerW * CGFloat(0.25 + 0.55 * pulse))
        let x = inset + (innerW - fw) * phase
        fill.frame = CGRect(x: x, y: inset, width: fw, height: h - inset * 2)
    }

    deinit {
        stopAnimating()
    }
}
