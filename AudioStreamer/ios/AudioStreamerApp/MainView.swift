import SwiftUI

struct MainView: View {
    @ObservedObject var network = NetworkListener.shared
    @ObservedObject var audio = AudioEngine.shared
    
    @State private var volume: Float = 1.0
    @State private var isMuted: Bool = false
    @State private var isPlaying: Bool = true
    
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
            
            VStack(spacing: 20) {
                // Header Bar with Cancel / Disconnect button
                HStack {
                    Text("AudioStreamer")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if isConnected {
                        Button(action: {
                            network.disconnect()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Cancel")
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 25)
                
                // Mode Selector (if not connected)
                if !isConnected {
                    Picker("Connection Mode", selection: $connectionMode) {
                        Text("Wi-Fi Mode").tag(0)
                        Text("Direct USB Cable").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 24)
                }
                
                // Status Card
                VStack(spacing: 10) {
                    HStack {
                        Circle()
                            .fill(isConnected ? Color.green : Color.orange)
                            .frame(width: 12, height: 12)
                        
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
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.15))
                .cornerRadius(16)
                .padding(.horizontal, 20)
                
                // Mode Specific Connection UI
                if !isConnected {
                    if connectionMode == 1 {
                        VStack(spacing: 8) {
                            Image(systemName: "cable.connector")
                                .font(.system(size: 36))
                                .foregroundColor(.blue)
                                .padding(.top, 6)
                            
                            Text("Direct USB Cable Mode")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Plug in your USB cable and open the Desktop app on your PC.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(white: 0.10))
                        .cornerRadius(14)
                        .padding(.horizontal, 24)
                    } else {
                        VStack(spacing: 10) {
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
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .padding(.horizontal, 24)
                            
                            Button(action: {
                                showingScanner = true
                            }) {
                                HStack {
                                    Image(systemName: "qrcode.viewfinder")
                                    Text("Scan QR Code")
                                }
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                }
                
                // Media Controls (Only: Previous, Play/Pause, Next)
                if isConnected {
                    VStack(spacing: 12) {
                        Text("PC Media Controls")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .textCase(.uppercase)
                        
                        HStack(spacing: 35) {
                            // Previous Track
                            Button(action: {
                                network.sendMediaCommand("PREV")
                            }) {
                                Image(systemName: "backward.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(Color(white: 0.2))
                                    .clipShape(Circle())
                            }
                            
                            // Play / Pause (Pause / Resume)
                            Button(action: {
                                isPlaying.toggle()
                                network.sendMediaCommand("PLAY_PAUSE")
                            }) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundColor(.black)
                                    .frame(width: 65, height: 65)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(color: .white.opacity(0.3), radius: 8)
                            }
                            
                            // Next Track
                            Button(action: {
                                network.sendMediaCommand("NEXT")
                            }) {
                                Image(systemName: "forward.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(Color(white: 0.2))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Volume Controls
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
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
                        .padding(.horizontal, 28)
                    }
                    
                    // Mute / Unmute Button
                    Button(action: {
                        isMuted.toggle()
                        audio.setVolume(isMuted ? 0.0 : volume)
                    }) {
                        Image(systemName: isMuted ? "speaker.slash.circle.fill" : "speaker.wave.2.circle.fill")
                            .resizable()
                            .frame(width: 64, height: 64)
                            .foregroundColor(isMuted ? .red : .blue)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 8)
                    }
                }
                .padding(.bottom, 40)
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
