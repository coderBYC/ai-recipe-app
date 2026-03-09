import SwiftUI

/// Neobrutalist box: 2px black border + offset black block behind (solid shadow).
struct BoxStyle: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.boxCornerRadius

    func body(content: Content) -> some View {
        content
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.accentColor, lineWidth: AppTheme.boxBorderWidth)
            )
            .padding(.trailing, AppTheme.boxShadowOffset)
            .padding(.bottom, AppTheme.boxShadowOffset)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.accentColor)
            )
    }
}

extension View {
    func boxStyle(cornerRadius: CGFloat = AppTheme.boxCornerRadius) -> some View {
        modifier(BoxStyle(cornerRadius: cornerRadius))
    }
}
