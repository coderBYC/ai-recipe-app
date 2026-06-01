import SwiftUI
import SwiftData
import UIKit

private struct OnboardingImportRowModel: Identifiable {
    let id = UUID()
    let recipe: Recipe
}

/// Imports tab mock — plain list or legacy media-box + coach overlay.
struct OnboardingImportTabStepView: View {
    var embedsCoachOverlay: Bool = true
    var usesPlainLayout: Bool = false
    let onFlowCompleted: () -> Void

    @State private var listRevealed = false
    @State private var showCoach = false
    @State private var focusRowRect: CGRect?
    @State private var importRecipes: [Recipe] = []
    @State private var modelContainer: ModelContainer?

    private static let rowEntrance = Animation.spring(response: 0.55, dampingFraction: 0.84)
    private static let coachEntrance = Animation.easeInOut(duration: 0.45)

    var body: some View {
        Group {
            if usesPlainLayout {
                importList
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
            showCoach = false
            focusRowRect = nil
        }
    }

    private var importList: some View {
        ScrollView {
            VStack(spacing: 0) {
                importsNavHeader
                ForEach(Array(importRecipes.enumerated()), id: \.element.id) { index, recipe in
                    RecipeRowView(recipe: recipe)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .opacity(listRevealed ? (index == 0 ? 1.0 : 0.35) : 0)
                        .offset(y: listRevealed ? 0 : 18)
                        .animation(Self.rowEntrance.delay(Double(index) * 0.08), value: listRevealed)
                        .background(focusRowGeometryReader(isFocusRow: index == 0 && embedsCoachOverlay))
                        .onTapGesture {
                            guard index == 0, listRevealed else { return }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onFlowCompleted()
                        }
                        .anchorPreference(key: OnboardingImportFocusRowAnchorKey.self, value: .bounds) { index == 0 && embedsCoachOverlay ? $0 : nil }
                }
            }
        }
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
            .padding(.bottom, 4)
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
                    OnboardingCoachCallout(text: ImportOnboardingCoachStep.tapImportRow.coachText ?? "")
                        .position(x: coach.x, y: coach.y)
                        .opacity(showCoach ? 1 : 0)
                        .offset(y: showCoach ? 0 : 10)
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
        showCoach = false

        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }

        withAnimation(Self.rowEntrance) {
            listRevealed = true
        }

        guard embedsCoachOverlay, !usesPlainLayout else { return }

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

#Preview("Import tab — plain") {
    OnboardingImportTabStepView(usesPlainLayout: true, onFlowCompleted: {})
        .padding()
        .background(AppTheme.surface)
}

// MARK: - Legacy coach placement (media-box mode)

private enum OnboardingImportTabCoachOverlayLayout {
    static let coachGapBelowRow: CGFloat = 50
    static let coachMinDistanceFromBottom: CGFloat = 28

    static func coachCenter(containerSize: CGSize, row: CGRect?) -> CGPoint {
        let row = row ?? .zero
        return CGPoint(
            x: row.midX,
            y: min(containerSize.height - coachMinDistanceFromBottom, row.maxY + coachGapBelowRow)
        )
    }
}
