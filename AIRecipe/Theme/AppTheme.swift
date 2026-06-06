import SwiftUI
import UIKit

// MARK: - Black & white minimal theme

enum AppTheme {
    static let primary = Color.black
    static let primaryDark = Color(white: 0.15)
    static let surface = Color.white
    static let cardBackground = Color.white
    static let textPrimary = Color.black
    static let textSecondary = Color(white: 0.45)
    static let triedBadge = Color(white: 0.25)
    static let shadow = Color.black.opacity(0.06)
    static let shadowLight = Color.black.opacity(0.04)

    static let boxBorderWidth: CGFloat = 2
    static let boxCornerRadius: CGFloat = 6
    static let boxShadowOffset: CGFloat = 4

    private static var cachedBitterRegularPS: String?
    private static var cachedBitterBoldPS: String?
    private static var cachedLibreRegularPS: String?
    private static var cachedLibreBoldPS: String?
    private static var cachedNanumRegularPS: String?
    private static var cachedNanumBoldPS: String?
    private static var cachedNanumExtraBoldPS: String?

    /// Bitter (bundled `Bitter-VariableFont_wght.ttf`). Used for settings and meal plan body text.
    static func bitterFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
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
                return .custom(ps, size: size)
            }
        } else {
            if let ps = cachedBitterRegularPS ?? resolveBitterPostScript(bold: false) {
                cachedBitterRegularPS = ps
                return .custom(ps, size: size)
            }
        }
        return .system(size: size, weight: weight)
    }

    /// Libre Baskerville (bundled variable font). Default body/UI serif.
    static func libreBaskervilleFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let wantsBold: Bool
        switch weight {
        case .bold, .heavy, .black, .semibold:
            wantsBold = true
        default:
            wantsBold = false
        }
        if wantsBold {
            if let ps = cachedLibreBoldPS ?? resolveLibreBaskervillePostScript(bold: true) {
                cachedLibreBoldPS = ps
                return .custom(ps, size: size)
            }
        } else {
            if let ps = cachedLibreRegularPS ?? resolveLibreBaskervillePostScript(bold: false) {
                cachedLibreRegularPS = ps
                return .custom(ps, size: size)
            }
        }
        return .system(size: size, weight: weight)
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
        #if DEBUG
        print("AppTheme: Bitter not found. Add Bitter-VariableFont_wght.ttf to the target and Info.plist → UIAppFonts.")
        #endif
        return nil
    }

    private static func resolveLibreBaskervillePostScript(bold: Bool) -> String? {
        let staticCandidates: [String]
        if bold {
            staticCandidates = [
                "LibreBaskerville-Bold", "LibreBaskervilleBold",
            ]
        } else {
            staticCandidates = [
                "LibreBaskerville-Regular", "LibreBaskervilleRegular", "LibreBaskerville",
            ]
        }
        for name in staticCandidates where UIFont(name: name, size: 12) != nil {
            return name
        }
        for family in UIFont.familyNames where family.localizedCaseInsensitiveContains("libre") && family.localizedCaseInsensitiveContains("baskerville") {
            let names = UIFont.fontNames(forFamilyName: family)
            if bold {
                let pick = names.first { n in
                    n.localizedCaseInsensitiveContains("bold") || n.contains("700")
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
        #if DEBUG
        print("AppTheme: Libre Baskerville not found. Add LibreBaskerville-VariableFont_wght.ttf to the target and Info.plist → UIAppFonts.")
        #endif
        return nil
    }

    /// Nanum Myeongjo (bundled `nanum-myeongjo-latin-*.ttf`). Used for sign-in, screen titles, notes, cook mode.
    static func nanumMyeongjoFont(size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        if let ps = cachedNanumExtraBoldPS ?? resolveNanumMyeongjoPostScript(weight: .extraBold) {
            cachedNanumExtraBoldPS = ps
            return .custom(ps, size: size)
        }
        if let ps = cachedNanumBoldPS ?? resolveNanumMyeongjoPostScript(weight: .bold) {
            cachedNanumBoldPS = ps
            return .custom(ps, size: size)
        }
        if let ps = cachedNanumRegularPS ?? resolveNanumMyeongjoPostScript(weight: .regular) {
            cachedNanumRegularPS = ps
            return .custom(ps, size: size)
        }
        return .system(size: size, weight: weight)
    }

    private enum NanumResolvedWeight {
        case regular, bold, extraBold
    }

    private static func resolveNanumMyeongjoPostScript(weight: NanumResolvedWeight) -> String? {
        let staticCandidates: [String]
        switch weight {
        case .extraBold:
            staticCandidates = [
                "NanumMyeongjoExtraBold", "NanumMyeongjo-ExtraBold", "NanumMyeongjoOTFExtraBold",
                "NanumMyeongjo-800", "NanumMyeongjo800",
            ]
        case .bold:
            staticCandidates = [
                "NanumMyeongjoBold", "NanumMyeongjo-Bold", "NanumMyeongjoOTFBold",
                "NanumMyeongjo-700", "NanumMyeongjo700",
            ]
        case .regular:
            staticCandidates = [
                "NanumMyeongjo", "NanumMyeongjo-Regular", "NanumMyeongjoOTF", "NanumMyeongjoOTFRegular",
            ]
        }
        for name in staticCandidates where UIFont(name: name, size: 12) != nil {
            return name
        }
        for family in UIFont.familyNames where family.localizedCaseInsensitiveContains("nanum") {
            let names = UIFont.fontNames(forFamilyName: family)
            let pick: String?
            switch weight {
            case .extraBold:
                pick = names.first { n in
                    n.localizedCaseInsensitiveContains("extrabold")
                        || n.localizedCaseInsensitiveContains("extra bold")
                        || n.contains("800")
                        || n.localizedCaseInsensitiveContains("black")
                } ?? names.first { $0.localizedCaseInsensitiveContains("bold") }
            case .bold:
                pick = names.first { n in
                    (n.localizedCaseInsensitiveContains("bold") || n.contains("700"))
                        && !n.localizedCaseInsensitiveContains("extra")
                        && !n.contains("800")
                } ?? names.first
            case .regular:
                pick = names.first { n in
                    !n.localizedCaseInsensitiveContains("bold")
                        && !n.localizedCaseInsensitiveContains("italic")
                        && !n.contains("700")
                        && !n.contains("800")
                } ?? names.first
            }
            if let pick, UIFont(name: pick, size: 12) != nil { return pick }
        }
        #if DEBUG
        print("AppTheme: Nanum Myeongjo not found. Add nanum-myeongjo-latin-*.ttf to the target and Info.plist → UIAppFonts.")
        #endif
        return nil
    }

    /// Typography for `.appFont(_:)` — Libre Baskerville by default; `.notes` uses Nanum.
    static func font(_ style: FontStyle) -> Font {
        switch style {
        case .notes:
            return nanumFont(style)
        default:
            break
        }
        let weight: Font.Weight
        switch style {
        case .headlineBold, .titleBold:
            weight = .bold
        case .largeTitle, .title, .headline:
            weight = .semibold
        default:
            weight = (style.weight == .bold) ? .bold : .regular
        }
        return libreBaskervilleFont(size: style.size, weight: weight)
    }

    /// Nanum Myeongjo typography for sign-in, screen titles, notes, and cook mode.
    static func nanumFont(_ style: FontStyle) -> Font {
        nanumMyeongjoFont(size: style.size, weight: .heavy)
    }

    /// Bitter typography for settings and meal plan content.
    static func bitterFont(_ style: FontStyle) -> Font {
        let weight: Font.Weight
        switch style {
        case .headlineBold, .titleBold:
            weight = .bold
        case .largeTitle, .title, .headline:
            weight = .semibold
        default:
            weight = (style.weight == .bold) ? .bold : .regular
        }
        return bitterFont(size: style.size, weight: weight)
    }

    enum FontStyle {
        case largeTitle, title, title2, title3, headline, body, callout, caption, caption2
        case titleBold, headlineBold
        case notes
        case custom(size: CGFloat, weight: FontWeight = .regular)

        var size: CGFloat {
            switch self {
            case .largeTitle: return 28
            case .title: return 24
            case .title2: return 20
            case .title3: return 18
            case .headline, .headlineBold: return 16
            case .body: return 15
            case .notes: return 16
            case .callout: return 14
            case .caption: return 12
            case .caption2: return 11
            case .titleBold: return 20
            case .custom(let size, _): return size
            }
        }

        var weight: FontWeight {
            switch self {
            case .headlineBold, .titleBold: return .bold
            case .custom(_, let w): return w
            default: return .regular
            }
        }
    }

    enum FontWeight { case regular, bold }
}

extension View {
    func appFont(_ style: AppTheme.FontStyle) -> some View {
        font(AppTheme.font(style))
    }

    func nanumAppFont(_ style: AppTheme.FontStyle) -> some View {
        font(AppTheme.nanumFont(style))
    }

    func bitterAppFont(_ style: AppTheme.FontStyle) -> some View {
        font(AppTheme.bitterFont(style))
    }

    func errorPopup(message: Binding<String?>) -> some View {
        modifier(ErrorPopupModifier(message: message))
    }
}

private struct ErrorPopupModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message, !message.isEmpty {
                    ErrorPopupView(message: message) {
                        self.message = nil
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: message != nil)
    }
}

private struct ErrorPopupView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .padding(.top, 2)

            Text(message)
                .appFont(.callout)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(AppTheme.libreBaskervilleFont(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(6)
                    .background(Color.white.opacity(0.2), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.red.opacity(0.5), radius: 14, x: 0, y: 7)
    }
}
