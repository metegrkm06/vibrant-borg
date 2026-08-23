import SwiftUI

struct MainView: View {
    @ObservedObject var network = NetworkListener.shared
    @ObservedObject var audio = AudioEngine.shared
    
    @State private var volume: Float = 1.0
    @State private var isMuted: Bool = false
    
    @State private var manualIP: String = ""
    @State private var showingScanner: Bool = false
    
    @State private var connectionMode: Int = 0 // 0 = WiFi, 1 = USB
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                Text("AudioStreamer")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 40)
                
                Picker("Connection Mode", selection: $connectionMode) {
                    Text("Wi-Fi").tag(0)
                    Text("USB").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 40)
                .onChange(of: connectionMode) { newValue in
                    if newValue == 1 {
                        // Standard Windows IP when tethered to iPhone
                        manualIP = "172.20.10.2"
                    } else {
                        manualIP = ""
                    }
                }
                
                if connectionMode == 1 {
                    Text("Turn on 'Personal Hotspot' and plug in via USB. Then connect below.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                
                // Status Card
                VStack(spacing: 15) {
                    HStack {
                        Circle()
                            .fill(network.isConnected ? Color.green : Color.orange)
                            .frame(width: 15, height: 15)
                        
                        Text(network.isConnected ? "Connected" : "Searching...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Text(network.pcName)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    if network.isConnected {
                        HStack {
                            Text("Estimated Latency:")
                                .foregroundColor(.gray)
                            Text("\(audio.latencyMs) ms")
                                .fontWeight(.bold)
                                .foregroundColor(audio.latencyMs < 30 ? .green : .yellow)
                        }
                        .font(.footnote)
                        .padding(.top, 10)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.15))
                .cornerRadius(20)
                .padding(.horizontal, 20)
                
                // Manual Connection UI
                if !network.isConnected {
                    VStack(spacing: 15) {
                        Text("Or connect manually:")
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
                        .padding(.horizontal, 40)
                        
                        Button(action: {
                            showingScanner = true
                        }) {
                            HStack {
                                Image(systemName: "qrcode.viewfinder")
                                Text("Scan QR Code")
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .padding(.horizontal, 40)
                        }
                    }
                }
                
                Spacer()
                
                // Controls
                VStack(spacing: 40) {
                    // Volume
                    VStack(spacing: 15) {
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
                    
                    // Mute Button
                    Button(action: {
                        isMuted.toggle()
                        audio.setVolume(isMuted ? 0.0 : volume)
                    }) {
                        Image(systemName: isMuted ? "speaker.slash.circle.fill" : "speaker.wave.2.circle.fill")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundColor(isMuted ? .red : .blue)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 10)
                    }
                }
                .padding(.bottom, 60)
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
