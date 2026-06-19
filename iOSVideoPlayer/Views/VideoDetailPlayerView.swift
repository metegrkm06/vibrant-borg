import SwiftUI
import AVKit

struct CustomPlayerView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> PlayerUIView {
        return PlayerUIView(player: player)
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }
}

class PlayerUIView: UIView {
    var player: AVPlayer? {
        get { return playerLayer.player }
        set { playerLayer.player = newValue }
    }
    
    private var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
    
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    init(player: AVPlayer) {
        super.init(frame: .zero)
        self.player = player
        playerLayer.videoGravity = .resizeAspect
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct VideoDetailPlayerView: View {
    let url: URL
    let title: String
    @Environment(\.presentationMode) var presentationMode
    
    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isDraggingSlider = false
    @State private var showControls = true
    
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    init(url: URL, title: String) {
        self.url = url
        self.title = title
        self._player = State(initialValue: AVPlayer(url: url))
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Full Screen Video layer
            CustomPlayerView(player: player)
                .onTapGesture {
                    withAnimation {
                        showControls.toggle()
                    }
                }
            
            // Custom Playback controls overlay
            if showControls {
                VStack {
                    // Top Bar
                    HStack {
                        Button(action: {
                            player.pause()
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.leading, 8)
                        
                        Spacer()
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Middle skip controls
                    HStack(spacing: 40) {
                        Button(action: { skip(by: -15) }) {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        Button(action: togglePlay) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .padding(18)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        Button(action: { skip(by: 15) }) {
                            Image(systemName: "goforward.15")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    
                    Spacer()
                    
                    // Bottom seek bar and times
                    VStack(spacing: 8) {
                        HStack {
                            Text(formatTime(currentTime))
                                .font(.caption)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text(formatTime(duration))
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)
                        
                        Slider(value: Binding(get: {
                            return currentTime
                        }, set: { newValue in
                            currentTime = newValue
                            if !isDraggingSlider {
                                isDraggingSlider = true
                            }
                        }), in: 0...max(1, duration), onEditingChanged: { editing in
                            if !editing {
                                seek(to: currentTime)
                                isDraggingSlider = false
                            }
                        })
                        .accentColor(.blue)
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 20)
                    .background(LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }
            }
        }
        .statusBar(hidden: !showControls)
        .onAppear {
            player.play()
            isPlaying = true
            
            if let item = player.currentItem {
                let asset = item.asset
                // Safe duration calculation
                if #available(iOS 15.0, *) {
                    Task {
                        if let dur = try? await asset.load(.duration) {
                            DispatchQueue.main.async {
                                self.duration = dur.seconds
                            }
                        }
                    }
                } else {
                    self.duration = asset.duration.seconds
                }
            }
        }
        .onReceive(timer) { _ in
            guard !isDraggingSlider else { return }
            currentTime = player.currentTime().seconds
            
            // Loop or reset back to zero if finished
            if currentTime >= duration - 0.5 && duration > 0 {
                isPlaying = false
                player.seek(to: .zero)
                currentTime = 0
            }
        }
        .onDisappear {
            player.pause()
        }
    }
    
    private func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    private func skip(by seconds: Double) {
        let currentSecs = player.currentTime().seconds
        let newSecs = max(0, min(duration, currentSecs + seconds))
        seek(to: newSecs)
    }
    
    private func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time)
        currentTime = seconds
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
