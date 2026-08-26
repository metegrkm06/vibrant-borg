import SwiftUI

struct ConnectionView: View {
    @ObservedObject var sender = VideoSender.shared
    @ObservedObject var discovery = NetworkDiscovery.shared
    @ObservedObject var camera = CameraManager.shared

    @State private var connectionMode: Int = 0 // 0 = USB, 1 = Wi-Fi
    @State private var manualIP: String = ""
    @State private var showScanner: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)

                VStack(spacing: 20) {
                    // Header Logo & Title
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundColor(.blue)

                        Text("BonayCamera")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))

                        Text("Turn your iPhone into a pro PC webcam")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 20)

                    // Mode Segmented Picker
                    Picker("Connection Mode", selection: $connectionMode) {
                        Text("⚡ Direct USB Cable").tag(0)
                        Text("🌐 Wi-Fi LAN").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 20)

                    if connectionMode == 0 {
                        // ── USB Cable Mode ──
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 100, height: 100)
                                Image(systemName: "cable.connector")
                                    .font(.system(size: 44))
                                    .foregroundColor(.blue)
                            }
                            .padding(.top, 10)

                            Text("Zero Latency USB Cable Mode")
                                .font(.headline)

                            Text("1. Connect iPhone to PC with USB Lightning/Type-C cable\n2. Open BonayCamera on PC\n3. Stream starts automatically with 0ms delay!")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)

                            Button(action: {
                                CameraManager.shared.start()
                                sender.isConnected = true
                                sender.isUSBMode = true
                            }) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Start Local Preview")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                                .padding(.horizontal, 30)
                            }
                        }
                        .transition(.opacity)
                    } else {
                        // ── Wi-Fi Mode ──
                        VStack(spacing: 16) {
                            // QR Scanner Button
                            Button(action: { showScanner = true }) {
                                HStack {
                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.system(size: 20))
                                    Text("Scan PC QR Code")
                                        .font(.headline)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.indigo)
                                .cornerRadius(12)
                                .padding(.horizontal, 30)
                            }

                            // Manual IP Input
                            HStack {
                                TextField("Enter PC IP (e.g. 192.168.1.50)", text: $manualIP)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.numbersAndPunctuation)
                                    .autocapitalization(.none)

                                Button("Connect") {
                                    guard !manualIP.isEmpty else { return }
                                    discovery.connect(toIP: manualIP.trimmingCharacters(in: .whitespaces))
                                }
                                .font(.headline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .padding(.horizontal, 30)

                            // Discovered PCs List
                            if !discovery.discoveredPCs.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Discovered PCs on Wi-Fi:")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.horizontal, 30)

                                    ForEach(discovery.discoveredPCs) { pc in
                                        Button(action: { discovery.connect(to: pc) }) {
                                            HStack {
                                                Image(systemName: "desktopcomputer")
                                                Text(pc.name)
                                                    .fontWeight(.semibold)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .foregroundColor(.gray)
                                            }
                                            .padding()
                                            .background(Color(UIColor.secondarySystemBackground))
                                            .cornerRadius(10)
                                            .padding(.horizontal, 30)
                                        }
                                    }
                                }
                            }
                        }
                        .transition(.opacity)
                    }

                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showScanner) {
                ScannerView { scannedCode in
                    // Format: bonaycamera://192.168.1.50 or raw IP
                    let cleaned = scannedCode.replacingOccurrences(of: "bonaycamera://", with: "")
                    manualIP = cleaned
                    discovery.connect(toIP: cleaned)
                }
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
    }
}
