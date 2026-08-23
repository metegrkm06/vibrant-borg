import SwiftUI
import AVFoundation

@main
struct AudioStreamerApp: App {
    init() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
