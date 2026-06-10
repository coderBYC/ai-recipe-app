import SwiftUI

struct GroceryListPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ComingSoonTabContent(
                title: "Grocery List",
                subtitle: "Build a shopping list from your meal plan and recipes.",
                systemImage: "cart.fill"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Grocery")
                        .nanumAppFont(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
    }
}
