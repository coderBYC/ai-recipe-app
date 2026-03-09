import SwiftUI

// MARK: - Black & white minimal theme

enum AppTheme {
    static let primary = Color.accentColor
    static let primaryDark = Color(white: 0.15)
    static let surface = Color.white
    static let cardBackground = Color.white
    static let textPrimary = Color.black
    static let textSecondary = Color(white: 0.45)
    static let triedBadge = Color(white: 0.25)
    static let shadow = Color.black.opacity(0.06)
    static let shadowLight = Color.black.opacity(0.04)

    /// Neobrutalist box: 2px black border + offset black block behind.
    static let boxBorderWidth: CGFloat = 2
    static let boxCornerRadius: CGFloat = 6
    static let boxShadowOffset: CGFloat = 4
}

// MARK: - Roboto Slab (custom font)
// 1. Download https://fonts.google.com/specimen/Roboto+Slab → add RobotoSlab-Regular.ttf and RobotoSlab-Bold.ttf (or RobotoSlab-VariableFont_wght.ttf)
// 2. In Xcode: drag the .ttf file(s) into the AIRecipe group (or Fonts folder). Check "Copy items if needed" and "Add to targets: AIRecipeApp"
// 3. Info.plist has UIAppFonts with the font filenames.

extension AppTheme {
    private static let robotoSlabBoldCandidates = ["RobotoSlab-Bold", "RobotoSlabBold", "RobotoSlab_700Bold", "Roboto Slab Bold"]

    private static var _resolvedBold: String?

    static func font(_ style: FontStyle) -> Font {
        let size = style.size
        return safeCustomFont(size: size, candidates: robotoSlabBoldCandidates, resolved: &_resolvedBold, label: "bold")
    }

    /// Resolve font name from candidates or from family "Roboto Slab", then return Font.
    private static func safeCustomFont(size: CGFloat, candidates: [String], resolved: inout String?, label: String) -> Font {
        if let name = resolved {
            if UIFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        for candidate in candidates {
            if UIFont(name: candidate, size: size) != nil {
                resolved = candidate
                #if DEBUG
                print("AppTheme: Loaded \(label) font: \(candidate)")
                #endif
                return .custom(candidate, size: size)
            }
        }
        let familyNames = UIFont.familyNames.filter { $0.localizedCaseInsensitiveContains("Roboto Slab") || $0.localizedCaseInsensitiveContains("RobotoSlab") }
        for family in familyNames {
            let names = UIFont.fontNames(forFamilyName: family)
            let prefer = label == "bold" ? names.first { $0.localizedCaseInsensitiveContains("Bold") || $0.localizedCaseInsensitiveContains("700") } ?? names.first
                : names.first { !$0.localizedCaseInsensitiveContains("Bold") && !$0.localizedCaseInsensitiveContains("Italic") } ?? names.first
            if let face = prefer, UIFont(name: face, size: size) != nil {
                resolved = face
                #if DEBUG
                print("AppTheme: Loaded \(label) font from family '\(family)': \(face)")
                #endif
                return .custom(face, size: size)
            }
        }
        #if DEBUG
        if resolved == nil {
            print("AppTheme: Roboto Slab not found. Add RobotoSlab-Regular.ttf and RobotoSlab-Bold.ttf (or RobotoSlab-VariableFont_wght.ttf) to the app target and to Info.plist → Fonts provided by application (UIAppFonts).")
        }
        #endif
        return .system(size: size, weight: .bold)
    }

    enum FontStyle {
        case largeTitle, title, title2, title3, headline, body, callout, caption, caption2
        case titleBold, headlineBold
        case custom(size: CGFloat, weight: FontWeight = .regular)

        var size: CGFloat {
            switch self {
            case .largeTitle: return 28
            case .title: return 24
            case .title2: return 20
            case .title3: return 18
            case .headline, .headlineBold: return 16
            case .body: return 15
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
}
