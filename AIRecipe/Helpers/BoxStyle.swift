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
                    .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
            )
            .padding(.trailing, 4)
            .padding(.bottom, 4)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black)
            )
    }
}

extension View {
    func boxStyle(cornerRadius: CGFloat = AppTheme.boxCornerRadius) -> some View {
        modifier(BoxStyle(cornerRadius: cornerRadius))
    }
}
