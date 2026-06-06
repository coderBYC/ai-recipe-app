import UIKit

/// Libre Baskerville for UIKit labels in the share extension (matches main app body font).
enum ShareExtensionFonts {
    private static var cachedLibreRegularPS: String?
    private static var cachedLibreBoldPS: String?

    static func libreBaskerville(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let wantsBold: Bool
        switch weight {
        case .bold, .heavy, .black, .semibold:
            wantsBold = true
        default:
            wantsBold = false
        }
        if wantsBold {
            if let ps = cachedLibreBoldPS ?? resolveLibrePostScript(bold: true) {
                cachedLibreBoldPS = ps
                if let f = UIFont(name: ps, size: size) { return f }
            }
        } else {
            if let ps = cachedLibreRegularPS ?? resolveLibrePostScript(bold: false) {
                cachedLibreRegularPS = ps
                if let f = UIFont(name: ps, size: size) { return f }
            }
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    /// Backward-compatible alias.
    static func bitter(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        libreBaskerville(size: size, weight: weight)
    }

    private static func resolveLibrePostScript(bold: Bool) -> String? {
        let staticCandidates: [String]
        if bold {
            staticCandidates = ["LibreBaskerville-Bold", "LibreBaskervilleBold"]
        } else {
            staticCandidates = ["LibreBaskerville-Regular", "LibreBaskervilleRegular", "LibreBaskerville"]
        }
        for name in staticCandidates where UIFont(name: name, size: 12) != nil {
            return name
        }
        for family in UIFont.familyNames where family.localizedCaseInsensitiveContains("libre") && family.localizedCaseInsensitiveContains("baskerville") {
            let names = UIFont.fontNames(forFamilyName: family)
            let pick: String?
            if bold {
                pick = names.first { $0.localizedCaseInsensitiveContains("bold") || $0.contains("700") } ?? names.first
            } else {
                pick = names.first {
                    !$0.localizedCaseInsensitiveContains("bold")
                        && !$0.localizedCaseInsensitiveContains("italic")
                        && !$0.contains("700")
                } ?? names.first
            }
            if let pick, UIFont(name: pick, size: 12) != nil { return pick }
        }
        return nil
    }
}
