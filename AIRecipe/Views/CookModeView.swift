import SwiftUI

struct CookModeView: View {
    
    @Bindable var recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex: Int = 0
    @State private var timerSeconds: Int = 0
    @State private var isTimerRunning: Bool = false
    
    var steps: [String] {
        recipe.stepLines
    }
    
    var body: some View {
        
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Background tap layer (doesn't block buttons)
            GeometryReader { _ in
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { previousStep() }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { nextStep() }
                }
            }
            
            VStack {
                
                // Top bar
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.callout)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                    }
                    
                }
                .padding()
                
                // Progress bars
                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i <= stepIndex ? Color.white : Color.gray.opacity(0.4))
                            .frame(height: 6)
                            
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Step text
                if !steps.isEmpty {
                    Text(steps[stepIndex])
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .fontDesign(.serif)
                }
                
                Spacer()
                
                // Timer controls
                VStack(spacing: 8) {
                    Text(timeString(from: timerSeconds))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 16) {
                        Button {
                            if timerSeconds >= 10 { timerSeconds -= 10 }
                        } label: {
                            Text("-10s")
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Color.white, in: Capsule())
                        }
                        
                        Button {
                            isTimerRunning.toggle()
                        } label: {
                            Text(isTimerRunning ? "Pause" : "Start")
                                .foregroundStyle(.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.white, in: Capsule())
                        }
                        
                        Button {
                            timerSeconds += 10
                        } label: {
                            Text("+10s")
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Color.white, in: Capsule())
                        }
                    }
                }
                .padding(.bottom, 16)
                
                // Step counter
                Text("\(stepIndex + 1) / \(steps.count)")
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 24)
            }
        }
        // Swipe left/right to navigate steps
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let threshold: CGFloat = 50
                    if value.translation.width < -threshold {
                        nextStep()
                    } else if value.translation.width > threshold {
                        previousStep()
                    }
                }
        )
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if isTimerRunning, timerSeconds > 0 {
                timerSeconds -= 1
            } else if isTimerRunning, timerSeconds == 0 {
                isTimerRunning = false
            }
        }
    }
    
    func nextStep() {
        if stepIndex < steps.count - 1 {
            stepIndex += 1
        }
    }
    
    func previousStep() {
        if stepIndex > 0 {
            stepIndex -= 1
        }
    }
    
    private func timeString(from totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
}

