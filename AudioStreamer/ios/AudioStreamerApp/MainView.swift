import SwiftUI

struct MainView: View {
    @ObservedObject var network = NetworkListener.shared
    @ObservedObject var audio = AudioEngine.shared
    
    @State private var volume: Float = 1.0
    @State private var isMuted: Bool = false
    
    @State private var manualIP: String = ""
    @State private var showingScanner: Bool = false
    @State private var connectionMode: Int = 0 // 0 = Wi-Fi, 1 = Direct USB Cable
    
    var isConnected: Bool {
        network.isConnected || audio.isUSBConnected
    }
    
    var statusTitle: String {
        if audio.isUSBConnected {
            return "Connected via USB Cable (0ms)"
        } else if network.isConnected {
            return "Connected via Wi-Fi"
        } else {
            return connectionMode == 1 ? "Waiting for USB Cable..." : "Searching on Wi-Fi..."
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 25) {
                Text("AudioStreamer")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 30)
                
                // Mode Selector
                Picker("Connection Mode", selection: $connectionMode) {
                    Text("Wi-Fi Mode").tag(0)
                    Text("Direct USB Cable").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 30)
                
                // Status Card
                VStack(spacing: 12) {
                    HStack {
                        Circle()
                            .fill(isConnected ? Color.green : Color.orange)
                            .frame(width: 14, height: 14)
                        
                        Text(statusTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    if audio.isUSBConnected {
                        Text("Direct Hardware Stream • No Network Delay")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    } else if network.isConnected {
                        Text(network.pcName)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    if isConnected {
                        HStack {
                            Text("Latency:")
                                .foregroundColor(.gray)
                            Text(audio.isUSBConnected ? "< 5 ms" : "\(audio.latencyMs) ms")
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                        .font(.footnote)
                        .padding(.top, 4)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.15))
                .cornerRadius(18)
                .padding(.horizontal, 20)
                
                // Mode Specific Info / Action
                if !isConnected {
                    if connectionMode == 1 {
                        // Direct USB Info
                        VStack(spacing: 10) {
                            Image(systemName: "cable.connector")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                                .padding(.top, 10)
                            
                            Text("Direct USB Cable Mode")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Plug your iPhone into your PC with a USB cable and launch the Desktop app. No Hotspot or Wi-Fi needed!")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(white: 0.10))
                        .cornerRadius(15)
                        .padding(.horizontal, 25)
                    } else {
                        // Wi-Fi Connection UI
                        VStack(spacing: 12) {
                            Text("Manual Wi-Fi Connection")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            HStack {
                                TextField("192.168.X.X", text: $manualIP)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.decimalPad)
                                
                                Button("Connect") {
                                    if !manualIP.isEmpty {
                                        network.connectToPC(ip: manualIP, name: "Manual PC")
                                    }
                                }
                                .padding(.horizontal, 15)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .padding(.horizontal, 30)
                            
                            Button(action: {
                                showingScanner = true
                            }) {
                                HStack {
                                    Image(systemName: "qrcode.viewfinder")
                                    Text("Scan QR Code")
                                }
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .padding(.horizontal, 30)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Controls
                VStack(spacing: 30) {
                    // Volume Slider
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "speaker.fill")
                                .foregroundColor(.gray)
                            
                            Slider(value: $volume, in: 0...2.0, step: 0.05)
                                .accentColor(.blue)
                                .onChange(of: volume) { newValue in
                                    if !isMuted {
                                        audio.setVolume(newValue)
                                    }
                                }
                            
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 30)
                    }
                    
                    // Mute / Unmute Button
                    Button(action: {
                        isMuted.toggle()
                        audio.setVolume(isMuted ? 0.0 : volume)
                    }) {
                        Image(systemName: isMuted ? "speaker.slash.circle.fill" : "speaker.wave.2.circle.fill")
                            .resizable()
                            .frame(width: 70, height: 70)
                            .foregroundColor(isMuted ? .red : .blue)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 10)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingScanner) {
            ScannerView { code in
                showingScanner = false
                var ip = code
                if code.hasPrefix("audiostreamer://") {
                    ip = code.replacingOccurrences(of: "audiostreamer://", with: "")
                }
                network.connectToPC(ip: ip, name: "QR Connection")
            }
            .edgesIgnoringSafeArea(.all)
        }
    }
}
