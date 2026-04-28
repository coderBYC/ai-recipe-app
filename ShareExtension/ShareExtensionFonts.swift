import UIKit

/// Bitter for UIKit labels in the share extension (matches main app `AppTheme.bitterFont` resolution).
enum ShareExtensionFonts {
    private static var cachedBitterRegularPS: String?
    private static var cachedBitterBoldPS: String?

    static func bitter(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let wantsBold: Bool
        switch weight {
        case .bold, .heavy, .black, .semibold:
            wantsBold = true
        default:
            wantsBold = false
        }
        if wantsBold {
            if let ps = cachedBitterBoldPS ?? resolveBitterPostScript(bold: true) {
                cachedBitterBoldPS = ps
                if let f = UIFont(name: ps, size: size) { return f }
            }
        } else {
            if let ps = cachedBitterRegularPS ?? resolveBitterPostScript(bold: false) {
                cachedBitterRegularPS = ps
                if let f = UIFont(name: ps, size: size) { return f }
            }
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    private static func resolveBitterPostScript(bold: Bool) -> String? {
        let staticCandidates: [String]
        if bold {
            staticCandidates = [
                "Bitter-Bold", "BitterBold", "Bitter_700Bold", "Bitter Roman Bold", "BitterRoman-Bold",
            ]
        } else {
            staticCandidates = [
                "Bitter-Regular", "BitterRegular", "Bitter Roman", "BitterRoman-Regular", "Bitter",
            ]
        }
        for name in staticCandidates where UIFont(name: name, size: 12) != nil {
            return name
        }
        for family in UIFont.familyNames where family.localizedCaseInsensitiveContains("bitter") {
            let names = UIFont.fontNames(forFamilyName: family)
            if bold {
                let pick = names.first { n in
                    n.localizedCaseInsensitiveContains("bold")
                        || n.contains("700")
                        || n.localizedCaseInsensitiveContains("black")
                } ?? names.first
                if let pick, UIFont(name: pick, size: 12) != nil { return pick }
            } else {
                let pick = names.first { n in
                    !n.localizedCaseInsensitiveContains("bold")
                        && !n.localizedCaseInsensitiveContains("italic")
                        && !n.contains("700")
                } ?? names.first
                if let pick, UIFont(name: pick, size: 12) != nil { return pick }
            }
        }
        return nil
    }
}
