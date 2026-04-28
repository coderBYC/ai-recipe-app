//
//  OnBoardingView.swift
//  AIRecipeApp
//
//  Guided first-run: screenshots + TipKit, real Import / Recipe / Edit / Cook / Meal Plan,
//  then sign up, paywall, welcome, and Home.
//

import SwiftUI
import SwiftData
import TipKit
import RevenueCatUI
import UIKit

// MARK: - Steps

private enum WalkStep: Int, CaseIterable {
    case splash = 0
    case tutorialIntro
    case imageShare
    case imageAppIcon
    case imageExtension
    case chromeImports
    case chromeRecipe
    case chromeEdit
    case chromeScroll
    case chromeCook
    case chromeMealPlan
    case thankYou
    case auth
    case welcome
}

struct OnboardingView: View {
    @Binding var isFinished: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager

    @State private var step: WalkStep = .splash
    @State private var tutorialRecipe: Recipe?
    @State private var chromeTab: AppTab = .cookbook
    @State private var showEditSheet = false
    @State private var showCookMode = false
    @State private var showPaywallSheet = false
    @State private var didSeedTutorial = false
    /// SwiftData id for any recipe created during the walkthrough (Add to Home or sample shortcut).
    @State private var onboardingTutorialRecipeID: UUID?

    private static let tutorialSourceURL = "onboarding://demo/reel"

    var body: some View {
        ZStack {
            AppTheme.surface.ignoresSafeArea()

            if !showEditSheet && !showCookMode {
                mainStepLayer
            }
        }
        .animation(.easeInOut(duration: 0.22), value: step)
        .animation(.easeInOut(duration: 0.22), value: showEditSheet)
        .animation(.easeInOut(duration: 0.22), value: showCookMode)
        .onChange(of: step) { _, new in
            syncChromeTab(for: new)
            if new == .chromeImports { seedTutorialSubmissionIfNeeded() }
        }
        .onChange(of: authManager.authState) { _, new in
            if step == .auth, new == .authenticated {
                showPaywallSheet = true
            }
        }
        .fullScreenCover(isPresented: $showEditSheet, onDismiss: {
            if step == .chromeEdit {
                chromeTab = .home
                step = .chromeScroll
            }
        }) {
            if let tutorialRecipe {
                RecipeEditView(recipe: tutorialRecipe, onDismiss: { showEditSheet = false })
                    .environment(\.isOnboardingWalkthrough, true)
            }
        }
        .fullScreenCover(isPresented: $showCookMode, onDismiss: {
            if step == .chromeCook {
                chromeTab = .mealPlan
                step = .chromeMealPlan
            }
        }) {
            if let tutorialRecipe {
                CookModeView(recipe: tutorialRecipe, onboardingVoiceShortcuts: true)
            }
        }
        .sheet(isPresented: $showPaywallSheet) {
            RevenueCatUI.PaywallView(displayCloseButton: true)
                .onPurchaseCompleted { _, _ in
                    Task { @MainActor in
                        await SubscriptionManager.shared.refreshAndSyncPlan()
                        showPaywallSheet = false
                        step = .welcome
                    }
                }
                .onRestoreCompleted { _ in
                    Task { @MainActor in
                        await SubscriptionManager.shared.refreshAndSyncPlan()
                        showPaywallSheet = false
                        step = .welcome
                    }
                }
                .onRequestedDismissal {
                    showPaywallSheet = false
                    step = .welcome
                }
        }
    }

    @ViewBuilder
    private var mainStepLayer: some View {
        ZStack {
            Group {
                switch step {
                case .splash:
                    splashPage
                case .tutorialIntro:
                    introPage
                case .imageShare:
                    screenshotPage(
                        assetName: "OnboardingShare",
                        systemFallback: "square.and.arrow.up",
                        tip: OnboardingShareTip(),
                        message: "Click share to send a recipe link into AI Recipe."
                    )
                case .imageAppIcon:
                    screenshotPage(
                        assetName: "OnboardingAppIcon",
                        systemFallback: "app.badge",
                        tip: OnboardingAppIconTip(),
                        message: "Tap the AI Recipe icon in the share row."
                    )
                case .imageExtension:
                    screenshotPage(
                        assetName: "OnboardingShareExtension",
                        systemFallback: "rectangle.on.rectangle.angled",
                        tip: OnboardingShareExtensionTip(),
                        message: "Tap “View recipe in app” when you see the banner in the share flow."
                    )
                case .chromeImports, .chromeMealPlan:
                    interactiveChrome
                case .chromeRecipe:
                    if let tutorialRecipe {
                        RecipePageView(recipe: tutorialRecipe, onDismiss: {})
                            .environment(\.isOnboardingWalkthrough, true)
                    }
                case .chromeScroll:
                    if let tutorialRecipe {
                        RecipePageView(recipe: tutorialRecipe, onDismiss: {})
                            .environment(\.isOnboardingWalkthrough, true)
                            .overlay(alignment: .bottom) {
                                VStack(spacing: 10) {
                                    Text("Scroll down to see ingredients, steps, and more.")
                                        .appFont(.callout)
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .padding(12)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                    Button("I’ve scrolled") {
                                        step = .chromeCook
                                        showCookMode = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(AppTheme.primary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 100)
                            }
                    }
                case .chromeEdit, .chromeCook:
                    Color.clear
                case .thankYou:
                    thankYouPage
                case .auth:
                    authPage
                case .welcome:
                    welcomePage
                }
            }

            if shouldShowBottomChrome {
                VStack {
                    Spacer()
                    bottomBar
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }

        }
    }

    private var shouldShowBottomChrome: Bool {
        switch step {
        case .splash, .auth, .welcome, .chromeEdit, .chromeCook, .chromeScroll:
            return false
        default:
            return true
        }
    }

    // MARK: - Pages

    private var splashPage: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(AppTheme.bitterFont(size: 72, weight: .regular))
                    .foregroundStyle(AppTheme.primary)
                Text("Let Him Cook")
                    .appFont(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            Text("Turn reels into real recipes.")
                .appFont(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                step = .tutorialIntro
            } label: {
                Text("Start")
                    .appFont(.headlineBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    private var introPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Quick tour")
                .appFont(.largeTitle)
                .fontWeight(.bold)
            Text("A few annotated screenshots, then the real Imports tab, recipe page, editor, cook mode, and meal plan.")
                .appFont(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 28)
            Spacer()
        }
    }

    private func screenshotPage(assetName: String, systemFallback: String, tip: some Tip, message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .appFont(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            onboardingImage(named: assetName, systemName: systemFallback)
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black, lineWidth: AppTheme.boxBorderWidth)
                )
                .padding(.horizontal, 16)
                .popoverTip(tip, arrowEdge: .bottom)

            Spacer(minLength: 0)
        }
    }

    private func onboardingImage(named: String, systemName: String) -> some View {
        Group {
            if UIImage(named: named) != nil {
                Image(named)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: systemName)
                        .font(AppTheme.bitterFont(size: 56, weight: .regular))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Add “\(named)” to Assets.xcassets (photo slot).")
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.cardBackground)
            }
        }
    }

    private var interactiveChrome: some View {
        VStack(spacing: 0) {
            if step == .chromeImports {
                Text("Take a look at the generated recipe — tap the import row.")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.cardBackground)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(AppTheme.shadow),
                        alignment: .bottom
                    )
                    .popoverTip(OnboardingImportReadyTip(), arrowEdge: .bottom)
            } else if step == .chromeMealPlan {
                Text("Add your recipe for tomorrow’s lunch — tap Add recipe on a meal row.")
                    .appFont(.callout)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.surface.opacity(0.95))
            }

            Group {
                switch chromeTab {
                case .home:
                    RecipeListView(addSheet: .constant(nil))
                case .cookbook:
                    ImportView(onTutorialAddedRecipe: { recipe in
                        registerTutorialRecipe(recipe)
                        chromeTab = .home
                        step = .chromeRecipe
                    })
                case .mealPlan:
                    MealPlanView()
                        .environment(\.isOnboardingWalkthrough, true)
                case .settings:
                    VStack(spacing: 12) {
                        Text("You’re almost done — you can open Settings anytime after the tour.")
                            .appFont(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            miniTabBar
        }
    }

    private var miniTabBar: some View {
        HStack(spacing: 0) {
            obTab(icon: "house.fill", title: "Home", tab: .home)
            obTab(icon: "square.and.arrow.up", title: "Imports", tab: .cookbook)
            Color.clear.frame(width: 52, height: 52)
            obTab(icon: "calendar", title: "Meal Plan", tab: .mealPlan)
            obTab(icon: "gearshape.fill", title: "Settings", tab: .settings)
        }
        .padding(.horizontal)
        .frame(height: 72)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func obTab(icon: String, title: String, tab: AppTab) -> some View {
        Button {
            chromeTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(AppTheme.bitterFont(size: 22, weight: .regular))
                    .foregroundStyle(chromeTab == tab ? AppTheme.primary : .gray)
                Text(title)
                    .font(AppTheme.bitterFont(size: 10, weight: .medium))
                    .foregroundStyle(chromeTab == tab ? AppTheme.primary : .gray)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var thankYouPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Thanks for trying AI Recipe!")
                .appFont(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text("Create an account to save recipes and sync across devices.")
                .appFont(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
    }

    private var authPage: some View {
        NavigationStack {
            RegistrationView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") {
                            showPaywallSheet = true
                        }
                        .appFont(.body)
                    }
                }
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("You’re in!")
                .appFont(.largeTitle)
                .fontWeight(.bold)
            Text("Your Home tab is ready. Paste links from Instagram, TikTok, or YouTube anytime.")
                .appFont(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
            Button {
                cleanupTutorialArtifacts()
                isFinished = true
            } label: {
                Text("Go to Home")
                    .appFont(.headlineBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step == .tutorialIntro {
                Button("Skip tour") {
                    cleanupTutorialArtifacts()
                    step = .thankYou
                }
                .appFont(.body)
                .foregroundStyle(AppTheme.textSecondary)
            }

            if step == .chromeImports {
                Button("Use sample recipe") {
                    insertSampleRecipeIfNeeded()
                    chromeTab = .home
                    step = .chromeRecipe
                }
                .appFont(.body)
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 0)

            Button(primaryBottomTitle) {
                advance()
            }
            .appFont(.headlineBold)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 10))
            .disabled(!canPrimaryAdvance)
            .opacity(canPrimaryAdvance ? 1 : 0.45)
        }
    }

    private var canPrimaryAdvance: Bool {
        switch step {
        case .chromeImports:
            return tutorialRecipe != nil
        default:
            return true
        }
    }

    private var primaryBottomTitle: String {
        switch step {
        case .splash: return "Start"
        case .tutorialIntro: return "Next"
        case .imageShare, .imageAppIcon, .imageExtension: return "Next"
        case .chromeImports: return "Next"
        case .chromeRecipe: return "Open editor"
        case .chromeMealPlan: return "Continue"
        case .thankYou: return "Sign up"
        default: return "Next"
        }
    }

    private func advance() {
        switch step {
        case .splash:
            step = .tutorialIntro
        case .tutorialIntro:
            step = .imageShare
        case .imageShare:
            step = .imageAppIcon
        case .imageAppIcon:
            step = .imageExtension
        case .imageExtension:
            step = .chromeImports
            chromeTab = .cookbook
        case .chromeImports:
            guard tutorialRecipe != nil else { return }
            chromeTab = .home
            step = .chromeRecipe
        case .chromeRecipe:
            step = .chromeEdit
            showEditSheet = true
        case .chromeMealPlan:
            step = .thankYou
        case .thankYou:
            step = .auth
        default:
            break
        }
    }

    private func syncChromeTab(for s: WalkStep) {
        switch s {
        case .chromeImports:
            chromeTab = .cookbook
        case .chromeRecipe, .chromeScroll:
            chromeTab = .home
        case .chromeMealPlan:
            chromeTab = .mealPlan
        default:
            break
        }
    }

    // MARK: - Data

    private func registerTutorialRecipe(_ recipe: Recipe) {
        tutorialRecipe = recipe
        onboardingTutorialRecipeID = recipe.id
    }

    private func seedTutorialSubmissionIfNeeded() {
        guard !didSeedTutorial else { return }
        didSeedTutorial = true
        let sub = RecipeImportSubmission(
            importKind: "link",
            sourceURL: Self.tutorialSourceURL,
            languageCode: "en"
        )
        sub.status = .ready
        sub.readyTitle = "Demo: Miso ramen bowl"
        sub.readyCreator = "Chef Tutorial"
        sub.readyNotes = "A sample import so you can preview the flow."
        sub.readyIngredients = "🍜 Fresh noodles - 200g\n🥚 Egg - 1\n🧄 Garlic - 2 cloves"
        sub.readySteps = "Simmer broth and season.\nCook noodles; soft-boil the egg.\nAssemble and garnish."
        sub.readyPrepMinutes = 10
        sub.readyCookMinutes = 20
        sub.readyTotalSteps = 3
        sub.readySource = RecipeSource.youtube.rawValue
        sub.readySourceURL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        sub.readyDownloadedVideoURL = ""
        sub.readyDishHeroSeconds = 1
        modelContext.insert(sub)
        try? modelContext.save()
    }

    private func insertSampleRecipeIfNeeded() {
        guard tutorialRecipe == nil else { return }
        let r = Recipe(
            title: "Demo: Miso ramen bowl",
            source: .youtube,
            sourceURL: Self.tutorialSourceURL,
            creator: "Chef Tutorial",
            ingredients: "🍜 Fresh noodles - 200g\n🥚 Egg - 1\n🧄 Garlic - 2 cloves",
            estimatedCookingMinutes: 20,
            prepMinutes: 10,
            totalSteps: 3,
            notes: "Tutorial sample",
            stepsContent: "Simmer broth and season.\nCook noodles; soft-boil the egg.\nAssemble and garnish."
        )
        modelContext.insert(r)
        registerTutorialRecipe(r)
        try? modelContext.save()
    }

    private func cleanupTutorialArtifacts() {
        if let rid = onboardingTutorialRecipeID {
            let desc = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.id == rid })
            if let rows = try? modelContext.fetch(desc) {
                for r in rows { modelContext.delete(r) }
            }
        }
        let marker = Self.tutorialSourceURL
        let subDesc = FetchDescriptor<RecipeImportSubmission>(
            predicate: #Predicate<RecipeImportSubmission> { $0.sourceURL == marker }
        )
        if let subs = try? modelContext.fetch(subDesc) {
            for s in subs { modelContext.delete(s) }
        }
        let orphanDesc = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.sourceURL == marker })
        if let orphans = try? modelContext.fetch(orphanDesc) {
            for r in orphans { modelContext.delete(r) }
        }
        try? modelContext.save()
        tutorialRecipe = nil
        onboardingTutorialRecipeID = nil
        didSeedTutorial = false
    }
}
