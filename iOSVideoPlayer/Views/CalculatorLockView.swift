import SwiftUI
import UIKit

struct CalculatorLockView: View {
    @Binding var isUnlocked: Bool
    @AppStorage("vaultPassword") private var vaultPassword = "6767"
    
    @State private var displayValue = "0"
    @State private var runningNumber = 0.0
    @State private var currentOperation: Operation = .none
    @State private var enterNewNumber = true
    
    @State private var secretBuffer = ""
    @State private var failedAttempts = 0
    
    let buttons: [[CalcButton]] = [
        [.clear, .negative, .percent, .divide],
        [.seven, .eight, .nine, .multiply],
        [.four, .five, .six, .subtract],
        [.one, .two, .three, .add],
        [.zero, .decimal, .equal]
    ]
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 12) {
                HStack {
                    Menu {
                        Button("Send Webhook") {
                            WebhookManager.shared.sendPasswordAlert(password: vaultPassword, combination: "password × =")
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 40)
                
                Spacer()
                
                HStack {
                    Spacer()
                    Text(displayValue)
                        .font(.system(size: 80, weight: .light))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding()
                
                ForEach(buttons, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { button in
                            Button(action: {
                                buttonTapped(button)
                            }) {
                                Text(button.title)
                                    .font(.system(size: 32, weight: .regular))
                                    .frame(width: buttonWidth(button), height: buttonHeight())
                                    .background(button.backgroundColor)
                                    .foregroundColor(button.foregroundColor)
                                    .cornerRadius(buttonHeight() / 2)
                            }
                        }
                    }
                }
            }
            .padding(.bottom)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            isUnlocked = false
        }
    }
    
    private func buttonTapped(_ button: CalcButton) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        
        switch button {
        case .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine:
            if enterNewNumber {
                displayValue = button.title
                enterNewNumber = false
            } else {
                displayValue += button.title
            }
            secretBuffer += button.title
        case .decimal:
            if enterNewNumber {
                displayValue = "0."
                enterNewNumber = false
            } else if !displayValue.contains(".") {
                displayValue += "."
            }
            secretBuffer += button.title
        case .clear:
            displayValue = "0"
            runningNumber = 0.0
            currentOperation = .none
            enterNewNumber = true
            secretBuffer = ""
        case .add, .subtract, .multiply, .divide:
            if let value = Double(displayValue) {
                runningNumber = value
            }
            currentOperation = button.operation
            enterNewNumber = true
            secretBuffer += button.title
        case .equal:
            secretBuffer += "="
            if secretBuffer == "\(vaultPassword)×=" {
                withAnimation(.spring()) {
                    isUnlocked = true
                }
                secretBuffer = ""
                failedAttempts = 0
            } else {
                if secretBuffer.hasSuffix("×=") || (secretBuffer.contains("×") && secretBuffer.hasSuffix("=")) {
                    failedAttempts += 1
                    if failedAttempts >= 3 {
                        WebhookManager.shared.sendIntruderAlert(failedAttempts: failedAttempts, lastAttempt: displayValue)
                    }
                }
                secretBuffer = ""
                
                if let value = Double(displayValue) {
                    let result = calculate(runningNumber, value, currentOperation)
                    displayValue = formatResult(result)
                    runningNumber = result
                }
                currentOperation = .none
                enterNewNumber = true
            }
        case .negative:
            if let value = Double(displayValue) {
                displayValue = formatResult(value * -1)
            }
        case .percent:
            if let value = Double(displayValue) {
                displayValue = formatResult(value / 100)
            }
        }
    }
    
    private func calculate(_ a: Double, _ b: Double, _ op: Operation) -> Double {
        switch op {
        case .add: return a + b
        case .subtract: return a - b
        case .multiply: return a * b
        case .divide: return b != 0 ? a / b : 0
        case .none: return b
        }
    }
    
    private func formatResult(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
    
    private func buttonWidth(_ button: CalcButton) -> CGFloat {
        let spacing: CGFloat = 12
        let totalSpacing = spacing * 5
        let screenWidth = UIScreen.main.bounds.width
        let w = (screenWidth - totalSpacing) / 4
        if button == .zero {
            return w * 2 + spacing
        }
        return w
    }
    
    private func buttonHeight() -> CGFloat {
        let spacing: CGFloat = 12
        let totalSpacing = spacing * 5
        let screenWidth = UIScreen.main.bounds.width
        return (screenWidth - totalSpacing) / 4
    }
}

enum Operation {
    case add, subtract, multiply, divide, none
}

enum CalcButton: String {
    case zero = "0"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"
    case add = "+"
    case subtract = "−"
    case multiply = "×"
    case divide = "÷"
    case equal = "="
    case clear = "C"
    case decimal = "."
    case percent = "%"
    case negative = "±"
    
    var title: String {
        return self.rawValue
    }
    
    var backgroundColor: Color {
        switch self {
        case .add, .subtract, .multiply, .divide, .equal:
            return .orange
        case .clear, .negative, .percent:
            return Color(UIColor.systemGray3)
        default:
            return Color(UIColor.systemGray6)
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .clear, .negative, .percent:
            return .black
        default:
            return .white
        }
    }
    
    var operation: Operation {
        switch self {
        case .add: return .add
        case .subtract: return .subtract
        case .multiply: return .multiply
        case .divide: return .divide
        default: return .none
        }
    }
}
