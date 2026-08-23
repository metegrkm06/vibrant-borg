import SwiftUI

struct MainView: View {
    @ObservedObject var network = NetworkListener.shared
    @ObservedObject var audio = AudioEngine.shared
    
    @State private var volume: Float = 1.0
    @State private var isMuted: Bool = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                Text("AudioStreamer")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 40)
                
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
    }
}
