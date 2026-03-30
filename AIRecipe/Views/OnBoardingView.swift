//
//  OnBoardingView.swift
//  AIRecipeApp
//
//  Created by Bryan Chen on 2026/3/30.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isFinished: Bool
    @State private var currentPage = 0
    
    var body: some View {
        ZStack {
            AppTheme.surface.ignoresSafeArea()
            
            TabView(selection: $currentPage) {
                // Page 1: The Tutorial Video
                OnboardingStepView(
                    title: "See the Magic",
                    description: "Paste any video link. Get the recipe instantly.",
                    isLast: false,
                    action: { currentPage = 1 }
                ) {
                   // TutorialVideoView() // Your screen recording box
                }
                .tag(0)
                
                // Page 2: Social Media Habit
                OnboardingStepView(
                    title: "Screen Time",
                    description: "How many hours do you spend on Social Media daily?",
                    isLast: false,
                    action: { currentPage = 2 }
                ) {
                    OnboardingPickerView(options: ["< 1hr", "1-3hrs", "3-5hrs", "5hrs+"])
                }
                .tag(1)
                
                // Page 3: Cooking Frequency
                OnboardingStepView(
                    title: "Cooking Habits",
                    description: "How often do you cook from Social Media recipes?",
                    isLast: true,
                    action: { isFinished = true }
                ) {
                    OnboardingPickerView(options: ["Never", "Rarely", "Weekly", "Daily"])
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            // This makes the dots visible on the white/surface background
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
}

struct OnboardingStepView<Content: View>: View {
    let title: String
    let description: String
    let isLast: Bool
    let action: () -> Void
    let content: Content
    
    init(title: String, description: String, isLast: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.isLast = isLast
        self.action = action
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 12) {
                Text(title)
                    .appFont(.largeTitle)
                    .fontWeight(.black)
                
                Text(description)
                    .appFont(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            // Your custom box style applied to the content (Video or Picker)
            content
                .frame(maxWidth: .infinity)
                .frame(height: 350)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black, lineWidth: 3)
                )
                .padding(.trailing, 4)
                .padding(.bottom, 4)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
                .padding(.horizontal, 24)

            Button(action: action) {
                Text(isLast ? "START COOKING" : "NEXT")
                    .appFont(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
    }
}

struct OnboardingPickerView: View {
    let options: [String]
    @State private var selection: String? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    HStack {
                        Text(option)
                            .appFont(.headline)
                        Spacer()
                        if selection == option {
                            Image(systemName: "checkmark.square.fill")
                        } else {
                            Image(systemName: "square")
                        }
                    }
                    .foregroundStyle(.black)
                    .padding()
                    .background(selection == option ? Color.black.opacity(0.1) : Color.clear)
                    .border(Color.black, width: selection == option ? 2 : 0)
                }
            }
        }
        .padding(20)
    }
}

#Preview("Onboarding Flow") {
    // We use .constant so the "Start Cooking" button won't
    // actually close the preview, letting you stay on the page.
    OnboardingView(isFinished: .constant(false))
        .environment(\.font, .system(.body, design: .monospaced)) // Optional: adds to the B&W aesthetic
}

#Preview("Single Step - Survey") {
    ZStack {
        Color.white.ignoresSafeArea()
        OnboardingStepView(
            title: "Cooking Habits",
            description: "How often do you cook from Social Media recipes?",
            isLast: true,
            action: {}
        ) {
            OnboardingPickerView(options: ["Never", "Rarely", "Weekly", "Daily"])
        }
    }
}


