import SwiftUI
import TipKit

// MARK: - TipKit (optional hints during the guided walkthrough)

struct OnboardingShareTip: Tip {
    var title: Text { Text("Share a recipe") }
    var message: Text? { Text("Click share to send a link into AI Recipe.") }
}

struct OnboardingAppIconTip: Tip {
    var title: Text { Text("Open AI Recipe") }
    var message: Text? { Text("Tap the app icon in the share row.") }
}

struct OnboardingShareExtensionTip: Tip {
    var title: Text { Text("View in app") }
    var message: Text? { Text("Use “View recipe in app” after sharing.") }
}

struct OnboardingImportReadyTip: Tip {
    var title: Text { Text("Your import") }
    var message: Text? { Text("Take a look at the generated recipe.") }
}

struct OnboardingEditRecipeTip: Tip {
    var title: Text { Text("Edit your recipe") }
    var message: Text? { Text("Tap the pencil to change ingredients, steps, and more.") }
}

struct OnboardingReorderTip: Tip {
    var title: Text { Text("Reorder steps") }
    var message: Text? { Text("Drag the ≡ handle to swap step order.") }
}

struct OnboardingSaveEditsTip: Tip {
    var title: Text { Text("Save your edits") }
    var message: Text? { Text("Tap the checkmark when you’re done.") }
}

struct OnboardingCookVoiceTip: Tip {
    var title: Text { Text("Cook mode") }
    var message: Text? { Text("Try voice commands for hands-free cooking.") }
}

struct OnboardingTimerVoiceTip: Tip {
    var title: Text { Text("Set a timer") }
    var message: Text? { Text("Say something like “set timer to 5 minutes”.") }
}

struct OnboardingPauseTimerTip: Tip {
    var title: Text { Text("Pause") }
    var message: Text? { Text("Say “pause” to stop the countdown.") }
}

struct OnboardingFinishCookTip: Tip {
    var title: Text { Text("Finish cooking") }
    var message: Text? { Text("Tap the checkmark when you’re done.") }
}

struct OnboardingMealPlanAddTip: Tip {
    var title: Text { Text("Meal plan") }
    var message: Text? { Text("Add your recipe for tomorrow’s lunch.") }
}

enum OnboardingTipKitBootstrap {
    static func configureIfAvailable() {
        do {
            try Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault),
            ])
        } catch {
            #if DEBUG
            print("TipKit configure failed: \(error)")
            #endif
        }
    }
}
