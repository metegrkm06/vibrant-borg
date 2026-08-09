import SwiftUI

@main
struct iOSVideoPlayerApp: App {
    @State private var isUnlocked = false
    @StateObject private var viewModel = VideoLibraryViewModel()
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isUnlocked {
                    GalleryHomeView(viewModel: viewModel, isUnlocked: $isUnlocked)
                        .transition(.opacity)
                } else {
                    CalculatorLockView(isUnlocked: $isUnlocked, isDecoyMode: $viewModel.isDecoyMode)
                        .transition(.opacity)
                }
            }
            .animation(.spring(), value: isUnlocked)
            .preferredColorScheme(.dark)
        }
    }
}
