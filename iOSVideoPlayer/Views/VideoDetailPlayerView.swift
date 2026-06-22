import SwiftUI
import AVKit
import AVFoundation

struct CustomPlayerView: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity
    
    func makeUIView(context: Context) -> PlayerUIView {
        return PlayerUIView(player: player, videoGravity: videoGravity)
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
        uiView.setVideoGravity(videoGravity)
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
    
    init(player: AVPlayer, videoGravity: AVLayerVideoGravity) {
        super.init(frame: .zero)
        self.player = player
        playerLayer.videoGravity = videoGravity
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        playerLayer.videoGravity = gravity
    }
}

struct VideoDetailPlayerView: View {
    let videos: [Video]
    @State private var currentIndex: Int
    @Environment(\.presentationMode) var presentationMode
    
    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isDraggingSlider = false
    @State private var showControls = true
    
    // Custom feature states
    @State private var isMuted = false
    @State private var playbackSpeed: Float = 1.0
    @State private var isAspectFill = false
    @State private var showVRMode = false
    
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    private var currentVideo: Video? {
        guard currentIndex >= 0 && currentIndex < videos.count else { return nil }
        return videos[currentIndex]
    }
    
    private var url: URL {
        return currentVideo?.url ?? URL(fileURLWithPath: "")
    }
    
    private var title: String {
        return currentVideo?.title ?? "Video Player"
    }
    
    init(videos: [Video], startIndex: Int) {
        self.videos = videos
        self._currentIndex = State(initialValue: startIndex)
        let initialVideo = videos[startIndex]
        self._player = State(initialValue: AVPlayer(url: initialVideo.url))
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Full Screen Video layer with dynamic aspect ratio gravity
            CustomPlayerView(player: player, videoGravity: isAspectFill ? .resizeAspectFill : .resizeAspect)
                .onTapGesture {
                    withAnimation {
                        showControls.toggle()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 30, coordinateSpace: .local)
                        .onEnded { value in
                            let horizontalSwipe = value.translation.width
                            let verticalSwipe = value.translation.height
                            
                            if abs(horizontalSwipe) > abs(verticalSwipe) {
                                if horizontalSwipe < -50 {
                                    playNextVideo()
                                } else if horizontalSwipe > 50 {
                                    playPreviousVideo()
                                }
                            }
                        }
                )
            
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
                        
                        // VR Mode Button
                        Button(action: {
                            player.pause()
                            isPlaying = false
                            showVRMode = true
                        }) {
                            Text("VR")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.purple.opacity(0.8))
                                .clipShape(Circle())
                        }
                        
                        // Shuffle/Random Video Button
                        Button(action: playRandomVideo) {
                            Image(systemName: "shuffle")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        // Feature 1: Aspect Ratio/Crop Toggle (Aspect Fit vs Aspect Fill)
                        Button(action: toggleAspectRatio) {
                            Image(systemName: isAspectFill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right.and.arrow.up.right.and.arrow.down.left")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        // Feature 2: Playback Speed Control (1.0x, 1.25x, 1.5x, 2.0x)
                        Button(action: cycleSpeed) {
                            Text(String(format: "%.2fx", playbackSpeed))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        
                        // Toggle Mute / Sound Button
                        Button(action: toggleMute) {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
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
        .fullScreenCover(isPresented: $showVRMode, onDismiss: {
            player.play()
            isPlaying = true
            player.rate = playbackSpeed
        }) {
            VRPlayerView(url: url, title: title)
        }
        .statusBar(hidden: !showControls)
        .onAppear {
            player.play()
            isPlaying = true
            player.rate = playbackSpeed
            player.isMuted = isMuted
            
            if let item = player.currentItem {
                let asset = item.asset
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
            
            // Loop automatically when finished
            if currentTime >= duration - 0.5 && duration > 0 {
                player.seek(to: .zero)
                player.play()
                player.rate = playbackSpeed
                currentTime = 0
                isPlaying = true
            }
        }
        .onDisappear {
            player.pause()
        }
        .onChange(of: currentIndex) { newIndex in
            guard newIndex >= 0 && newIndex < videos.count else { return }
            let video = videos[newIndex]
            player.pause()
            
            let newPlayer = AVPlayer(url: video.url)
            self.player = newPlayer
            self.isPlaying = true
            self.currentTime = 0
            self.duration = 0
            
            newPlayer.play()
            newPlayer.rate = playbackSpeed
            newPlayer.isMuted = isMuted
            
            if let item = newPlayer.currentItem {
                let asset = item.asset
                Task {
                    if let dur = try? await asset.load(.duration) {
                        DispatchQueue.main.async {
                            self.duration = dur.seconds
                        }
                    }
                }
            }
        }
    }
    
    private func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
            player.rate = playbackSpeed
        }
        isPlaying.toggle()
    }
    
    private func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }
    
    private func cycleSpeed() {
        let speeds: [Float] = [1.0, 1.25, 1.5, 2.0]
        if let idx = speeds.firstIndex(of: playbackSpeed) {
            let nextIdx = (idx + 1) % speeds.count
            playbackSpeed = speeds[nextIdx]
            if isPlaying {
                player.rate = playbackSpeed
            }
        }
    }
    
    private func toggleAspectRatio() {
        withAnimation {
            isAspectFill.toggle()
        }
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
        if isPlaying {
            player.rate = playbackSpeed
        }
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
    
    private func playNextVideo() {
        guard !videos.isEmpty else { return }
        let nextIndex = (currentIndex + 1) % videos.count
        currentIndex = nextIndex
    }
    
    private func playPreviousVideo() {
        guard !videos.isEmpty else { return }
        let prevIndex = (currentIndex - 1 + videos.count) % videos.count
        currentIndex = prevIndex
    }
    
    private func playRandomVideo() {
        guard videos.count > 1 else { return }
        var randomIndex = Int.random(in: 0..<videos.count)
        while randomIndex == currentIndex {
            randomIndex = Int.random(in: 0..<videos.count)
        }
        currentIndex = randomIndex
    }
}
