//
//  OnboardingTypes.swift
//  AIRecipeApp
//
//  Shared onboarding types (in Helpers so they compile with OnboardingState.swift).
//

import SwiftUI

// MARK: - Bundle video

struct OnboardingBundleVideo: Equatable {
    let name: String
    let ext: String
}

// MARK: - Coach box styling

struct OnboardingCoachSpec {
    var text: String
    var font: AppTheme.FontStyle = .headline
    var textAlignment: TextAlignment = .center
    var cornerRadius: CGFloat = 8
    var paddingHorizontal: CGFloat = 16
    var paddingVertical: CGFloat = 14

    init(
        text: String,
        font: AppTheme.FontStyle = .headline,
        textAlignment: TextAlignment = .center,
        cornerRadius: CGFloat = 8,
        paddingHorizontal: CGFloat = 16,
        paddingVertical: CGFloat = 14
    ) {
        self.text = text
        self.font = font
        self.textAlignment = textAlignment
        self.cornerRadius = cornerRadius
        self.paddingHorizontal = paddingHorizontal
        self.paddingVertical = paddingVertical
    }
}

// MARK: - Spotlight targets (slides 6–9)

enum OnboardingSpotlightTarget: Hashable {
    case editButton
    case cookTimePlusButton
    case saveButton
    case stepsSection
}

enum OnboardingSpotlightCoordinateSpace {
    static let name = "onboardingSpotlight"
}

struct OnboardingSpotlightTargetRectKey: PreferenceKey {
    static var defaultValue: [OnboardingSpotlightTarget: CGRect] = [:]

    static func reduce(
        value: inout [OnboardingSpotlightTarget: CGRect],
        nextValue: () -> [OnboardingSpotlightTarget: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func onboardingSpotlightTarget(_ target: OnboardingSpotlightTarget) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: OnboardingSpotlightTargetRectKey.self,
                    value: [target: geo.frame(in: .named(OnboardingSpotlightCoordinateSpace.name))]
                )
            }
        }
    }
}

// MARK: - Import walkthrough coach steps

enum ImportOnboardingCoachStep: Int, CaseIterable, Comparable {
    case tapImportRow = 0
    case tapEdit
    case done

    static func < (lhs: ImportOnboardingCoachStep, rhs: ImportOnboardingCoachStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var slideTitle: String {
        switch self {
        case .tapImportRow:
            return "⑤ Tap All Your Generated Recipes In Import Tab"
        case .tapEdit:
            return "⑥ Tap Edit On Your Recipe"
        case .done:
            return ""
        }
    }

    var coachText: String? {
        switch self {
        case .tapImportRow:
            return "Click Your Generated Recipe Here!"
        case .tapEdit:
            return "Tap Edit"
        case .done:
            return nil
        }
    }
}

// MARK: - Cook Mode onboarding demo

enum OnboardingCookModeDemoTrigger: Equatable {
    case none
    case nextStep
    case setFiveMinutes
}

// MARK: - Import tab overlay geometry

enum OnboardingImportTabOverlayCoordinateSpace {
    static let name = "onboardingImportTabOverlay"
}

struct OnboardingImportFocusRowAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct OnboardingImportFocusRowRectKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}
