import SwiftUI

@main
struct iOSVideoPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            VideoGridView()
                .preferredColorScheme(.dark) // modern dark mode UI
        }
    }
}
