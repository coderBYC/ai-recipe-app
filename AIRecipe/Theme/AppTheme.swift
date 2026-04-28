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

    /// Bitter (bundled `Bitter-VariableFont_wght.ttf` and/or static Bitter .ttf). Resolves PostScript names at runtime.
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
        print("AppTheme: Bitter not found. Add Bitter .ttf to the target and Info.plist → UIAppFonts.")
        #endif
        return nil
    }

    /// Typography for `.appFont(_:)` — all Bitter.
    static func font(_ style: FontStyle) -> Font {
        let weight: Font.Weight
        switch style {
        case .headlineBold, .titleBold:
            weight = .bold
        case .largeTitle, .title, .headline:
            weight = .semibold
        default:
            weight = (style.weight == .bold) ? .bold : .semibold
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
                    .font(AppTheme.bitterFont(size: 12, weight: .bold))
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
