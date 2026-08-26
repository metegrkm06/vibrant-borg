import SwiftUI

struct MainCameraView: View {
    @ObservedObject var camera = CameraManager.shared
    @ObservedObject var sender = VideoSender.shared
    @ObservedObject var discovery = NetworkDiscovery.shared

    @State private var showSettings = false
    @State private var isBlackScreenActive = false
    @State private var showScanner = false

    var body: some View {
        ZStack {
            // ── 1. Live Camera Preview Layer ──
            CameraPreviewView(camera: camera)
                .edgesIgnoringSafeArea(.all)

            // ── 2. Rule of Thirds Grid Overlay ──
            if camera.isGridVisible {
                GridView()
                    .edgesIgnoringSafeArea(.all)
                    .allowsHitTesting(false)
            }

            // ── 3. Tap to Focus Animated Reticle ──
            if let focusPt = camera.focusPoint {
                GeometryReader { geo in
                    Rectangle()
                        .stroke(Color.yellow, lineWidth: 1.5)
                        .frame(width: 70, height: 70)
                        .position(x: focusPt.x * geo.size.width, y: focusPt.y * geo.size.height)
                        .animation(.easeInOut(duration: 0.2), value: focusPt)
                }
                .allowsHitTesting(false)
            }

            // ── 4. Main HUD Controls ──
            VStack {
                // ── Top Bar ──
                HStack(spacing: 12) {
                    // Exit / Disconnect Button
                    Button(action: {
                        sender.disconnect()
                        camera.stop()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Exit")
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.red.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }

                    Spacer()

                    // Connection Badge & Live Stats
                    HStack(spacing: 6) {
                        Circle()
                            .fill(sender.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(sender.isUSBMode ? "⚡ USB" : "🌐 Wi-Fi")
                            .font(.system(size: 12, weight: .bold))
                        Text(String(format: "%.0f FPS", camera.outputFPS))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.65))
                    .foregroundColor(.white)
                    .cornerRadius(15)

                    Spacer()

                    // Torch Button
                    if camera.selectedPosition != .front {
                        Button(action: { camera.toggleTorch() }) {
                            Image(systemName: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.system(size: 16))
                                .padding(8)
                                .background(camera.isTorchOn ? Color.yellow : Color.black.opacity(0.65))
                                .foregroundColor(camera.isTorchOn ? .black : .white)
                                .clipShape(Circle())
                        }
                    }

                    // Black Screen Battery Saver Button
                    Button(action: { isBlackScreenActive.toggle() }) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 16))
                            .padding(8)
                            .background(Color.black.opacity(0.65))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }

                    // Settings Button
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .padding(8)
                            .background(Color.black.opacity(0.65))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // ── Bottom Controls ──
                VStack(spacing: 12) {
                    // Zoom Switcher Pills (0.5x, 1.0x, 2.0x)
                    HStack(spacing: 10) {
                        if camera.availableCameras.contains(.backUltraWide) {
                            ZoomPillButton(title: "0.5x", isSelected: camera.selectedPosition == .backUltraWide) {
                                camera.switchCamera(to: .backUltraWide)
                            }
                        }

                        ZoomPillButton(title: "1.0x", isSelected: camera.selectedPosition == .backWide && camera.currentZoom <= 1.2) {
                            if camera.selectedPosition != .backWide {
                                camera.switchCamera(to: .backWide)
                            }
                            camera.setZoom(1.0)
                        }

                        if camera.availableCameras.contains(.backTelephoto) {
                            ZoomPillButton(title: "2.0x", isSelected: camera.selectedPosition == .backTelephoto) {
                                camera.switchCamera(to: .backTelephoto)
                            }
                        } else {
                            ZoomPillButton(title: "2.0x", isSelected: camera.currentZoom >= 1.8) {
                                if camera.selectedPosition != .backWide {
                                    camera.switchCamera(to: .backWide)
                                }
                                camera.setZoom(2.0)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(22)

                    // Action Toolbar: Mirror, Flip Camera, Rotate
                    HStack(spacing: 24) {
                        // Mirror Toggle
                        Button(action: { camera.toggleMirror() }) {
                            VStack(spacing: 3) {
                                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                                    .font(.system(size: 18))
                                Text("Mirror")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .frame(width: 54, height: 54)
                            .background(camera.isMirrored ? Color.blue.opacity(0.8) : Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                        }

                        // Flip Camera (Front / Back)
                        Button(action: {
                            if camera.selectedPosition == .front {
                                camera.switchCamera(to: .backWide)
                            } else {
                                camera.switchCamera(to: .front)
                            }
                        }) {
                            VStack(spacing: 3) {
                                Image(systemName: "camera.rotate.fill")
                                    .font(.system(size: 22))
                                Text(camera.selectedPosition == .front ? "Back" : "Front")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .frame(width: 64, height: 64)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                        }

                        // Rotation / Upside Down Fix
                        Button(action: { camera.cycleRotation() }) {
                            VStack(spacing: 3) {
                                Image(systemName: "rotate.right.fill")
                                    .font(.system(size: 18))
                                Text("\(camera.rotationAngle)°")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .frame(width: 54, height: 54)
                            .background(camera.rotationAngle != 0 ? Color.orange.opacity(0.8) : Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                        }
                    }
                    .padding(.bottom, 16)
                }
            }

            // ── 5. Black Screen Battery Saver Overlay ──
            if isBlackScreenActive {
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    VStack(spacing: 12) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)
                        Text("BonayCamera Streaming...")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Screen is black to save battery & reduce heat.\nTap anywhere to wake screen.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                    }
                }
                .onTapGesture {
                    isBlackScreenActive = false
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            CameraSettingsSheet(camera: camera)
        }
    }
}

// ─── Subviews ────────────────────────────────────────────────────────────────

struct ZoomPillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.yellow : Color.clear)
                .foregroundColor(isSelected ? .black : .white)
                .cornerRadius(12)
        }
    }
}

struct GridView: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                // Vertical lines
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: w * 2 / 3, y: 0))
                path.addLine(to: CGPoint(x: w * 2 / 3, y: h))
                // Horizontal lines
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: h * 2 / 3))
                path.addLine(to: CGPoint(x: w, y: h * 2 / 3))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
    }
}

struct CameraSettingsSheet: View {
    @ObservedObject var camera: CameraManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Resolution & Quality")) {
                    Picker("Resolution", selection: $camera.currentResolution) {
                        ForEach(ResolutionPreset.allCases) { res in
                            Text(res.rawValue).tag(res)
                        }
                    }
                    .onChange(of: camera.currentResolution) { newRes in
                        camera.setResolution(newRes)
                    }

                    Picker("Frame Rate", selection: $camera.currentFPS) {
                        Text("60 FPS (Ultra Smooth)").tag(60)
                        Text("30 FPS (Standard)").tag(30)
                        Text("24 FPS (Cinematic)").tag(24)
                        Text("15 FPS (Bandwidth Saver)").tag(15)
                    }
                    .onChange(of: camera.currentFPS) { newFPS in
                        camera.setFPS(newFPS)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("JPEG Quality")
                            Spacer()
                            Text("\(Int(camera.jpegQuality * 100))%")
                                .foregroundColor(.gray)
                        }
                        Slider(value: $camera.jpegQuality, in: 0.4...0.95, step: 0.05)
                    }
                }

                Section(header: Text("Overlays & Helpers")) {
                    Toggle("Rule of Thirds Grid", isOn: $camera.isGridVisible)
                    Toggle("Mirror Video (Horizontal Flip)", isOn: $camera.isMirrored)
                        .onChange(of: camera.isMirrored) { _ in
                            camera.toggleMirror()
                        }
                }

                Section(header: Text("Device Status")) {
                    HStack {
                        Text("Battery Level")
                        Spacer()
                        Text("\(Int(UIDevice.current.batteryLevel * 100))%")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Text("Thermal State")
                        Spacer()
                        Text(thermalStateString(ProcessInfo.processInfo.thermalState))
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Camera Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }

    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal (Cool)"
        case .fair:    return "Fair (Warm)"
        case .serious: return "Serious (Hot)"
        case .critical: return "Critical (Throttling)"
        @unknown default: return "Normal"
        }
    }
}
