import SwiftUI
import SwiftData
import UIKit

/// Imports tab mock — plain list with 👇 on first row + bottom prompt, or media-box + coach overlay.
struct OnboardingImportTabStepView: View {
    var embedsCoachOverlay: Bool = true
    var usesPlainLayout: Bool = false
    let onFlowCompleted: () -> Void
    @State private var listRevealed = false
    @State private var showPointer = false
    @State private var showBottomPrompt = false
    @State private var showCoach = false
    @State private var focusRowRect: CGRect?
    @State private var importRecipes: [Recipe] = []
    @State private var modelContainer: ModelContainer?

    private static let rowEntrance = Animation.spring(response: 0.55, dampingFraction: 0.84)
    private static let promptEntrance = Animation.spring(response: 0.5, dampingFraction: 0.84)
    private static let coachEntrance = Animation.easeInOut(duration: 0.45)

    private static let bottomPromptText = "Click Your Generated Recipe Here!"

    var body: some View {
        Group {
            if usesPlainLayout {
                plainImportLayout
            } else if embedsCoachOverlay {
                VStack(spacing: 20) {
                    OnboardingMediaBox {
                        ZStack {
                            importList
                            coachOverlay
                        }
                        .coordinateSpace(name: OnboardingImportTabOverlayCoordinateSpace.name)
                        .onPreferenceChange(OnboardingImportFocusRowRectKey.self) { rect in
                            if let rect, rect.width > 1, rect.height > 1 {
                                focusRowRect = rect
                            }
                        }
                    }
                    .padding(.horizontal, OnboardingMediaLayout.horizontalPadding)
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                importList
                    .coordinateSpace(name: OnboardingImportTabOverlayCoordinateSpace.name)
            }
        }
        .onAppear {
            if importRecipes.isEmpty, let pair = OnboardingImportStepMockData.makeImportListContainer() {
                modelContainer = pair.0
                importRecipes = pair.1
            }
        }
        .modifier(OnboardingImportTabModelContainer(container: modelContainer))
        .task {
            await runEntranceSequence()
        }
        .onDisappear {
            listRevealed = false
            showPointer = false
            showBottomPrompt = false
            showCoach = false
            focusRowRect = nil
        }
    }

    // MARK: - Plain layout (walkthrough slide 5)

    private var plainImportLayout: some View {
        ZStack(alignment: .topLeading) {
            importList
                .coordinateSpace(name: OnboardingImportTabOverlayCoordinateSpace.name)
                .onPreferenceChange(OnboardingImportFocusRowRectKey.self) { rect in
                    if let rect, rect.width > 1, rect.height > 1 {
                        focusRowRect = rect
                    }
                }

            if showPointer, let focusRowRect {
                OnboardingFlashingPointerEmojiView()
                    .position(
                        x: focusRowRect.midX + 140,
                        y: max(28, focusRowRect.minY - 15)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }

            if showBottomPrompt, let focusRowRect {
                OnboardingFlashingCoachBox(text: Self.bottomPromptText)
                    .frame(width: min(focusRowRect.width + 48, UIScreen.main.bounds.width - 32))
                    .position(
                        x: focusRowRect.midX,
                        y: focusRowRect.maxY + Self.plainCoachGapBelowRow + 360
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let plainCoachGapBelowRow: CGFloat = 22

    private var importList: some View {
        ScrollView {
            VStack(spacing: 0) {
                importsNavHeader
                ForEach(Array(importRecipes.enumerated()), id: \.element.id) { index, recipe in
                    RecipeRowView(recipe: recipe)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .offset(y: listRevealed ? 0 : 18)
                        .animation(Self.rowEntrance.delay(Double(index) * 0.08), value: listRevealed)
                        .background(focusRowGeometryReader(isFocusRow: index == 0))
                        .onTapGesture {
                            guard index == 0, listRevealed else { return }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onFlowCompleted()
                        }
                }
            }
        }
        .padding(.top, usesPlainLayout ? 8 : 20)
        .scrollIndicators(.hidden)
        .background(AppTheme.surface)
    }

    private var importsNavHeader: some View {
        Text("Imports")
            .appFont(.largeTitle)
            .fontWeight(.bold)
            .foregroundStyle(AppTheme.primary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }

    private var coachOverlay: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let coach = OnboardingImportTabCoachOverlayLayout.coachCenter(
                containerSize: size,
                row: focusRowRect
            )

            ZStack {
                if showCoach {
                    OnboardingFlashingCoachBox(text: Self.bottomPromptText)
                        .position(coach)
                       
                }
            }
            .allowsHitTesting(false)
            .animation(Self.coachEntrance, value: showCoach)
        }
    }

    private func focusRowGeometryReader(isFocusRow: Bool) -> some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: OnboardingImportFocusRowRectKey.self,
                    value: isFocusRow
                        ? geo.frame(in: .named(OnboardingImportTabOverlayCoordinateSpace.name))
                        : nil
                )
        }
    }

    @MainActor
    private func runEntranceSequence() async {
        listRevealed = false
        showPointer = false
        showBottomPrompt = false
        showCoach = false

        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }

        // 1) Import rows
        withAnimation(Self.rowEntrance) {
            listRevealed = true
        }

        if usesPlainLayout {
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }

            // 2) 👇 on first row
            withAnimation(Self.promptEntrance) {
                showPointer = true
            }

            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }

            // 3) Bottom prompt
            withAnimation(Self.promptEntrance) {
                showBottomPrompt = true
            }
            return
        }

        guard embedsCoachOverlay else { return }

        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }

        withAnimation(Self.coachEntrance) {
            showCoach = true
        }
    }
}

private struct OnboardingImportTabModelContainer: ViewModifier {
    let container: ModelContainer?

    func body(content: Content) -> some View {
        if let container {
            content.modelContainer(container)
        } else {
            content
        }
    }
}

// MARK: - Flashing 👇

struct OnboardingFlashingPointerEmojiView: View {
    var emoji: String = "👇"
    var fontSize: CGFloat = 60

    @State private var isVisible = false

    var body: some View {
        Text(emoji)
            .font(.system(size: fontSize))
            .opacity(isVisible ? 1 : 0.2)
            .scaleEffect(isVisible ? 1 : 0.92)
            .animation(
                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: isVisible
            )
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .accessibilityHidden(true)
    }
}

#Preview("Import tab — plain") {
    OnboardingImportTabStepView(usesPlainLayout: true, onFlowCompleted: {})
        .padding()
        .background(AppTheme.surface)
}

// MARK: - Legacy coach placement (media-box mode)

private enum OnboardingImportTabCoachOverlayLayout {
    static let coachGapBelowRow: CGFloat = 22
    static let coachMinDistanceFromBottom: CGFloat = 28

    static func coachCenter(containerSize: CGSize, row: CGRect?) -> CGPoint {
        let row = row ?? .zero
        return CGPoint(
            x: row.midX,
            y: min(containerSize.height - coachMinDistanceFromBottom, row.maxY + coachGapBelowRow)
        )
    }
}

struct OnboardingFlashing<Content: View>: View {
    var minOpacity: Double = 0.38
    var minScale: CGFloat = 0.98
    @ViewBuilder var content: () -> Content

    @State private var isPulsing = false

    var body: some View {
        content()
            .opacity(isPulsing ? 1 : minOpacity)
            .scaleEffect(isPulsing ? 1 : minScale)
            .animation(
                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .onDisappear { isPulsing = false }
    }
}

