import SwiftUI

struct FridgePlaceholderView: View {
    var body: some View {
        NavigationStack {
            ComingSoonTabContent(
                title: "Fridge",
                subtitle: "Track what’s in your fridge and what you need to restock.",
                systemImage: "refrigerator.fill"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Fridge")
                        .nanumAppFont(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
    }
}
