import SwiftUI
import AVFoundation

@main
struct IOSCameraStreamApp: App {
    @StateObject private var sender = VideoSender.shared
    @StateObject private var camera = CameraManager.shared

    init() {
        // Prevent screen dimming / sleep during live camera streaming
        UIApplication.shared.isIdleTimerDisabled = true

        // Configure audio session for background and mic support
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Audio session init error: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if sender.isConnected || camera.isRunning {
                MainCameraView()
            } else {
                ConnectionView()
            }
        }
    }
}
