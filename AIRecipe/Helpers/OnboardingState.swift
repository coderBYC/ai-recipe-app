//
//  OnboardingState.swift
//  AIRecipeApp
//

import SwiftUI

enum OnboardingStep: Int, CaseIterable, Comparable {
    case intro = 0

    // Pre-import
    case shareRecipe = 1
    case viewImportInApp = 2
    case recipeDoneNotification = 3

    // Import walkthrough (single persistent slide identity)
    case importTapRecipe = 4
    case importedRecipeShowcase = 5

    // Post-import walkthrough
    case recipePageTapSteps = 6
    case cookModeVoiceIntro = 7
    case mealPlanAddRecipe = 8
    case youAreDone = 9
    case signInAuth = 10

    static var stepCount: Int { allCases.count }

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var isSignInStep: Bool { self == .signInAuth }

    var importCoachStep: ImportOnboardingCoachStep? {
        switch self {
        case .importTapRecipe: return .tapImportRow
        default: return nil
        }
    }

    /// Keeps import sub-steps on one view so overlay + coach can animate between them.
    var slideIdentity: String {
        if importCoachStep != nil { return "import-walkthrough" }
        return "onboarding-\(rawValue)"
    }

    /// Customize coach box per slide in `OnboardingState.swift`.
    var coach: OnboardingCoachSpec {
        switch self {
        case .intro:
            return OnboardingCoachSpec(
                text: "Turn viral cooking videos into recipes you can actually cook.",
                font: .headline,
                textAlignment: .center
            )
        case .shareRecipe:
            return OnboardingCoachSpec(text: "Share the recipe", font: .headlineBold)
        case .viewImportInApp:
            return OnboardingCoachSpec(
                text: "Tap View Import In App (you can leave — it still imports in the Import tab!)",
                font: .headline
            )
        case .recipeDoneNotification:
            return OnboardingCoachSpec(text: "Your recipe is done!", font: .headlineBold)

        case .importTapRecipe:
            return OnboardingCoachSpec(text: ImportOnboardingCoachStep.tapImportRow.coachText ?? "", font: .headlineBold)

        case .importedRecipeShowcase:
            return OnboardingCoachSpec(
                text: "You can import every video to recipes like this!",
                font: .titleBold,
                textAlignment: .center
            )

        case .recipePageTapSteps:
            return OnboardingCoachSpec(text: "Click Steps To Enter Cook Mode", font: .headlineBold)

        case .cookModeVoiceIntro:
            return OnboardingCoachSpec(
                text: "Voice Commands Allow You To Control Timers And Navigate Steps Hands-Free",
                font: .headlineBold,
                textAlignment: .center
            )

        case .mealPlanAddRecipe:
            return OnboardingCoachSpec(text: "Add your recipe for tomorrow’s lunch!", font: .headlineBold)
        case .youAreDone:
            return OnboardingCoachSpec(text: "You’re done!", font: .titleBold)
        case .signInAuth:
            return OnboardingCoachSpec(
                text: "Sign in or create an account to save your recipes.",
                font: .headline
            )
        }
    }

    var coachmark: String { coach.text }

    /// Bundle video for share slide (add `onboarding-share-button.mp4` / `.mov` to the app target).
    static let shareButtonVideoName = "onboarding-share-button"
    static let shareButtonVideoExtension = "mp4"
    static let viewImportVideoName = "record-view-import"
    static let viewImportVideoExtension = "mov"
    static let mealPlanAddVideoName = "onboarding-meal-plan-add"
    static let mealPlanAddVideoExtension = "mov"

    static func bundleVideoExists(name: String, extension ext: String) -> Bool {
        Bundle.main.path(forResource: name, ofType: ext) != nil
    }

    /// Optional bundled screen recording for this step.
    var bundleVideo: OnboardingBundleVideo? {
        let candidate: (String, String)?
        switch self {
        case .shareRecipe:
            candidate = (Self.shareButtonVideoName, Self.shareButtonVideoExtension)
        case .viewImportInApp:
            candidate = (Self.viewImportVideoName, Self.viewImportVideoExtension)
        case .mealPlanAddRecipe:
            candidate = (Self.mealPlanAddVideoName, Self.mealPlanAddVideoExtension)
        default:
            candidate = nil
        }
        guard let candidate, Self.bundleVideoExists(name: candidate.0, extension: candidate.1) else {
            return nil
        }
        return OnboardingBundleVideo(name: candidate.0, ext: candidate.1)
    }

    /// Asset name in Assets.xcassets — drop your PNG into the matching imageset.
    var screenshotAssetName: String? {
        switch self {
        case .intro, .youAreDone, .signInAuth,
             .importTapRecipe,.importedRecipeShowcase,
             .recipePageTapSteps, .cookModeVoiceIntro:
            return nil
        case .shareRecipe:
            return "screenshot-share-sheet"
        case .viewImportInApp:
            return "screenshot-view-import"
        case .recipeDoneNotification:
            return "screenshot-notification"
        case .mealPlanAddRecipe:
            return "screenshot-meal-plan-add"
        }
    }

    var screenshotPlaceholderIcon: String {
        switch self {
        case .intro, .youAreDone, .signInAuth:
            return "photo"
        case .shareRecipe:
            return "square.and.arrow.up"
        case .viewImportInApp:
            return "arrow.up.forward.app"
        case .recipeDoneNotification:
            return "bell.badge"
        case .importTapRecipe, .importedRecipeShowcase:
            return "play.rectangle"
        case .recipePageTapSteps:
            return "list.number"
        case .cookModeVoiceIntro:
            return "mic.fill"
        case .mealPlanAddRecipe:
            return "calendar"
        }
    }
}
