import SwiftUI
import SwiftData

/// Single persistent import walkthrough — sub-steps share one container; plain layout on slides 5–6.
struct OnboardingImportWalkthroughView: View {
    let step: ImportOnboardingCoachStep
    let onFlowCompleted: () -> Void

    @State private var rowFocusRect: CGRect?
    @State private var cachedRowFocusRect: CGRect?

    private let preview = OnboardingImportStepMockData.makePreviewContainer()

    private static let transitionAnimation = Animation.easeInOut(duration: 0.48)

    /// No phone-frame border or gray coach overlay (import list + recipe edit intro).
    private var usesPlainPresentation: Bool {
        step == .tapImportRow || step == .tapEdit
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(step.slideTitle)
                .appFont(.titleBold)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
                .contentTransition(.opacity)
                .id(step.slideTitle)

            Group {
                if usesPlainPresentation {
                    mediaContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    OnboardingMediaBox {
                        mediaContent
                            .id(step)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                            .coordinateSpace(name: OnboardingImportTabOverlayCoordinateSpace.name)
                    }
                    .overlay {
                        animatedCoachOverlay
                    }
                }
            }
            .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Self.transitionAnimation, value: step)
        .onPreferenceChange(OnboardingImportFocusRowRectKey.self) { rect in
            guard !usesPlainPresentation else { return }
            guard let rect, rect.width > 1, rect.height > 1 else { return }
            rowFocusRect = rect
            cachedRowFocusRect = rect
        }
        .onChange(of: step) { _, newStep in
            if newStep == .tapImportRow, let cachedRowFocusRect {
                rowFocusRect = cachedRowFocusRect
            }
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        switch step {
        case .tapImportRow:
            OnboardingImportTabStepView(
                usesPlainLayout: true,
                onFlowCompleted: onFlowCompleted
            )
        case .tapEdit:
            if let preview {
                OnboardingRecipePageView(
                    recipe: preview.1,
                    onDismiss: {},
                    onOnboardingEditTapped: onFlowCompleted
                )
                .modelContainer(preview.0)
            } else {
                importPlaceholder
            }
        case .tapPlusOneMinute:
            if let preview {
                RecipeEditView(
                    recipe: preview.1,
                    onDismiss: {},
                    onboardingCoachText: ImportOnboardingCoachStep.tapPlusOneMinute.coachText,
                    onOnboardingCookTimePlusTapped: onFlowCompleted
                )
                .modelContainer(preview.0)
            } else {
                importPlaceholder
            }
        case .tapSave:
            if let preview {
                RecipeEditView(
                    recipe: preview.1,
                    onDismiss: {},
                    onboardingCoachText: ImportOnboardingCoachStep.tapSave.coachText,
                    onOnboardingSaved: onFlowCompleted
                )
                .modelContainer(preview.0)
            } else {
                importPlaceholder
            }
        case .done:
            EmptyView()
        }
    }

    private var importPlaceholder: some View {
        Text("Couldn't load preview.")
            .appFont(.headline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.surface)
    }

    private var animatedCoachOverlay: some View {
        GeometryReader { proxy in
            let layout = ImportOnboardingCoachOverlayLayout.layout(
                for: step,
                in: proxy.size,
                rowFocusRect: rowFocusRect ?? cachedRowFocusRect
            )

            ZStack {
                Color.gray.opacity(layout.grayOpacity)

                RoundedRectangle(cornerRadius: layout.holeCornerRadius)
                    .frame(width: layout.holeSize.width, height: layout.holeSize.height)
                    .position(x: layout.holeCenter.x, y: layout.holeCenter.y)
                    .blendMode(.destinationOut)

                OnboardingCoachCallout(text: step.coachText ?? "")
                    .position(x: layout.coachCenter.x, y: layout.coachCenter.y)
                    .id(step.coachText)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .compositingGroup()
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Overlay layout (tune hole / coach positions here)

private struct ImportOnboardingCoachOverlayLayout {
    let grayOpacity: Double
    let holeCenter: CGPoint
    let holeSize: CGSize
    let holeCornerRadius: CGFloat
    let coachCenter: CGPoint

    static func layout(
        for step: ImportOnboardingCoachStep,
        in size: CGSize,
        rowFocusRect: CGRect?
    ) -> ImportOnboardingCoachOverlayLayout {
        switch step {
        case .tapImportRow, .tapEdit:
            return ImportOnboardingCoachOverlayLayout(
                grayOpacity: 0,
                holeCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                holeSize: .zero,
                holeCornerRadius: 0,
                coachCenter: CGPoint(x: size.width / 2, y: size.height / 2)
            )

        case .tapPlusOneMinute:
            let holeW: CGFloat = 330
            let holeH: CGFloat = 100
            let holeY: CGFloat = 423
            return ImportOnboardingCoachOverlayLayout(
                grayOpacity: 0.78,
                holeCenter: CGPoint(x: size.width / 2 - 3, y: holeY),
                holeSize: CGSize(width: holeW, height: holeH),
                holeCornerRadius: 12,
                coachCenter: CGPoint(x: size.width - 100, y: 358)
            )

        case .tapSave:
            let holeW: CGFloat = 44
            let holeH: CGFloat = 44
            let trailing: CGFloat = 18
            let top: CGFloat = 22
            let holeX = size.width - trailing - holeW / 2 - 3
            let holeY = top + holeH / 2 - 12
            return ImportOnboardingCoachOverlayLayout(
                grayOpacity: 0.78,
                holeCenter: CGPoint(x: holeX, y: holeY),
                holeSize: CGSize(width: holeW, height: holeH),
                holeCornerRadius: 10,
                coachCenter: CGPoint(x: size.width - 90, y: 80)
            )

        case .done:
            return ImportOnboardingCoachOverlayLayout(
                grayOpacity: 0,
                holeCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                holeSize: .zero,
                holeCornerRadius: 0,
                coachCenter: CGPoint(x: size.width / 2, y: size.height / 2)
            )
        }
    }
}

#Preview("Import Walkthrough") {
    OnboardingImportWalkthroughView(step: .tapImportRow, onFlowCompleted: {})
        .padding()
}
