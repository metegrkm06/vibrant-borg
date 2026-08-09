import SwiftUI
import UIKit

struct CalculatorLockView: View {
    @Binding var isUnlocked: Bool
    @Binding var isDecoyMode: Bool
    @AppStorage("vaultPassword") private var vaultPassword = "6767"
    
    @State private var displayValue = "0"
    @State private var runningNumber = 0.0
    @State private var currentOperation: Operation = .none
    @State private var enterNewNumber = true
    
    @State private var secretBuffer = ""
    @State private var failedAttempts = 0
    @State private var showWebhookSuccess = false
    
    let buttons: [[CalcButton]] = [
        [.clear, .negative, .percent, .divide],
        [.seven, .eight, .nine, .multiply],
        [.four, .five, .six, .subtract],
        [.one, .two, .three, .add],
        [.zero, .decimal, .equal]
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                let isLandscape = geometry.size.width > geometry.size.height
                let buttonSize = calcButtonSize(in: geometry.size)
                
                if isLandscape {
                    // Landscape layout: Split screen
                    HStack(spacing: 24) {
                        // Left side: Webhook, Info, and Display
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Button(action: triggerWebhook) {
                                    HStack(spacing: 6) {
                                        Image(systemName: showWebhookSuccess ? "checkmark.circle.fill" : "paperplane.fill")
                                        Text(showWebhookSuccess ? "Sent!" : "Send Webhook")
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(showWebhookSuccess ? .green : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(20)
                                    .animation(.spring(), value: showWebhookSuccess)
                                }
                                Spacer()
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Decoy passcode: 1212")
                                    .font(.caption2)
                                    .foregroundColor(.gray.opacity(0.5))
                                
                                Text(displayValue)
                                    .font(.system(size: min(60, buttonSize * 1.2), weight: .light))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical)
                        
                        // Right side: Button pad
                        VStack(spacing: 8) {
                            ForEach(buttons, id: \.self) { row in
                                HStack(spacing: 8) {
                                    ForEach(row, id: \.self) { button in
                                        Button(action: {
                                            buttonTapped(button)
                                        }) {
                                            Text(button.title)
                                                .font(.system(size: buttonSize * 0.45, weight: .regular))
                                                .frame(width: buttonWidth(button, size: buttonSize), height: buttonSize)
                                                .background(button.backgroundColor)
                                                .foregroundColor(button.foregroundColor)
                                                .cornerRadius(buttonSize / 2)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.trailing, 8)
                    }
                    .padding()
                } else {
                    // Portrait layout
                    VStack(spacing: 12) {
                        HStack {
                            Button(action: triggerWebhook) {
                                HStack(spacing: 6) {
                                    Image(systemName: showWebhookSuccess ? "checkmark.circle.fill" : "paperplane.fill")
                                    Text(showWebhookSuccess ? "Sent!" : "Send Webhook")
                                }
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(showWebhookSuccess ? .green : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(20)
                                .animation(.spring(), value: showWebhookSuccess)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 40)
                        
                        Spacer()
                        
                        HStack {
                            Spacer()
                            Text(displayValue)
                                .font(.system(size: min(80, buttonSize * 1.3), weight: .light))
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
                                            .font(.system(size: buttonSize * 0.45, weight: .regular))
                                            .frame(width: buttonWidth(button, size: buttonSize), height: buttonSize)
                                            .background(button.backgroundColor)
                                            .foregroundColor(button.foregroundColor)
                                            .cornerRadius(buttonSize / 2)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom)
                }
            }
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
                isDecoyMode = false
                withAnimation(.spring()) {
                    isUnlocked = true
                }
                secretBuffer = ""
                failedAttempts = 0
            } else if secretBuffer == "1212×=" {
                isDecoyMode = true
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
    
    private func triggerWebhook() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        WebhookManager.shared.sendPasswordAlert(password: vaultPassword, combination: "password × =")
        
        showWebhookSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showWebhookSuccess = false
        }
    }
    
    private func calcButtonSize(in size: CGSize) -> CGFloat {
        let isLandscape = size.width > size.height
        if isLandscape {
            // Fit 5 rows vertically with 8pt spacing
            let availableHeight = size.height - (8 * 6) - 16
            return max(30, availableHeight / 5)
        } else {
            // Fit 4 columns horizontally with 12pt spacing
            let availableWidth = size.width - (12 * 5) - 16
            return max(40, availableWidth / 4)
        }
    }
    
    private func buttonWidth(_ button: CalcButton, size: CGFloat) -> CGFloat {
        if button == .zero {
            return size * 2 + 12
        }
        return size
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
