import Foundation
import Network
import AVFoundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Lock-free ring buffer for audio frames
// ─────────────────────────────────────────────────────────────────────────────
final class PCMRingBuffer {
    private let capacity: Int
    private var buffer: [UnsafeMutableRawPointer?]
    private var lengths: [Int]
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private var count: Int = 0
    private let lock = NSLock()

    init(capacity: Int = 64) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
        self.lengths = Array(repeating: 0, count: capacity)
    }

    deinit {
        for ptr in buffer { if let p = ptr { free(p) } }
    }

    func push(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        // Drop oldest if full
        if count == capacity {
            if let old = buffer[readIndex] { free(old) }
            buffer[readIndex] = nil
            readIndex = (readIndex + 1) % capacity
            count -= 1
        }
        let byteCount = data.count
        let ptr = malloc(byteCount)!
        data.withUnsafeBytes { memcpy(ptr, $0.baseAddress!, byteCount) }
        buffer[writeIndex] = ptr
        lengths[writeIndex] = byteCount
        writeIndex = (writeIndex + 1) % capacity
        count += 1
    }

    func pop() -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard count > 0, let ptr = buffer[readIndex] else { return nil }
        let byteCount = lengths[readIndex]
        let data = Data(bytes: ptr, count: byteCount)
        free(ptr)
        buffer[readIndex] = nil
        readIndex = (readIndex + 1) % capacity
        count -= 1
        return data
    }

    var available: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AudioEngine
// ─────────────────────────────────────────────────────────────────────────────
class AudioEngine: ObservableObject {
    static let shared = AudioEngine()

    @Published var latencyMs: Int = 0
    @Published var isUSBConnected: Bool = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let mixer = AVAudioMixerNode()

    private var udpListener: NWListener?
    private var tcpListener: NWListener?
    private var activeTCPConnection: NWConnection?

    // 48 kHz stereo Float32 non-interleaved
    private let floatFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000, channels: 2, interleaved: false)!

    private let ringBuffer = PCMRingBuffer(capacity: 128)

    // Separate high-priority audio render thread
    private var renderThread: Thread?
    private var renderRunning = false

    // Pre-allocate one AVAudioPCMBuffer that we reuse each frame
    private let frameCapacity: AVAudioFrameCount = 480   // 10 ms @ 48kHz
    private var renderBuffer: AVAudioPCMBuffer!

    // Soft-silence buffer for underrun concealment
    private var silenceBuffer: AVAudioPCMBuffer!

    init() {
        renderBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: frameCapacity)!
        silenceBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: frameCapacity)!
        silenceBuffer.frameLength = frameCapacity
        // zero-fill silence
        for ch in 0..<2 {
            memset(silenceBuffer.floatChannelData![ch], 0, Int(frameCapacity) * MemoryLayout<Float>.stride)
        }

        setupAudioSession()
        setupEngine()

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleEngineChange),
            name: .AVAudioEngineConfigurationChange, object: engine)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification, object: nil)

        startListeners()
        startRenderThread()
    }

    // MARK: Setup

    private func setupAudioSession() {
        do {
            let s = AVAudioSession.sharedInstance()
            // .playback + allowBluetoothA2DP for BT speakers/AirPods
            try s.setCategory(.playback, mode: .default,
                               options: [.allowBluetoothA2DP, .allowAirPlay])
            // Smallest possible hardware I/O buffer = lowest latency
            try s.setPreferredIOBufferDuration(0.005)   // 5 ms
            try s.setActive(true)
        } catch { print("AudioSession error: \(error)") }
    }

    private func setupEngine() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: floatFormat)
        do {
            try engine.start()
            player.play()
        } catch { print("Engine start error: \(error)") }
    }

    // MARK: Listeners

    private func startListeners() {
        startUDPListener()
        startTCPListener()
    }

    private func startUDPListener() {
        guard udpListener == nil else { return }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        do {
            udpListener = try NWListener(using: params, on: 5000)
            udpListener?.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global(qos: .userInteractive))
                self?.receiveUDP(conn)
            }
            udpListener?.start(queue: .global(qos: .userInteractive))
        } catch { print("UDP listen error: \(error)") }
    }

    private func receiveUDP(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if let data, data.count > 12 { self?.enqueueRaw(data) }
            if error == nil { self?.receiveUDP(conn) }
        }
    }

    private func startTCPListener() {
        guard tcpListener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        do {
            tcpListener = try NWListener(using: params, on: 5002)
            tcpListener?.newConnectionHandler = { [weak self] conn in
                self?.activeTCPConnection = conn
                conn.start(queue: .global(qos: .userInteractive))
                DispatchQueue.main.async {
                    self?.isUSBConnected = true
                    NetworkListener.shared.isConnected = true
                    NetworkListener.shared.pcName = "PC (Direct USB Cable)"
                }
                self?.readTCPLength(conn)
            }
            tcpListener?.start(queue: .global(qos: .userInteractive))
        } catch { print("TCP listen error: \(error)") }
    }

    private func readTCPLength(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, let data, data.count == 4, error == nil else {
                DispatchQueue.main.async {
                    self?.isUSBConnected = false
                    self?.activeTCPConnection = nil
                }
                return
            }
            let len = Int(data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            guard len > 12, len < 65536 else { self.readTCPLength(conn); return }
            self.readTCPBody(conn, remaining: len, accumulated: Data())
        }
    }

    private func readTCPBody(_ conn: NWConnection, remaining: Int, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else { return }
            var acc = accumulated
            acc.append(data)
            if acc.count >= remaining {
                if acc.count > 12 { self.enqueueRaw(acc) }
                self.readTCPLength(conn)
            } else {
                self.readTCPBody(conn, remaining: remaining - data.count, accumulated: acc)
            }
        }
    }

    // MARK: Packet → Ring Buffer

    private func enqueueRaw(_ data: Data) {
        // Strip 12-byte header, push raw PCM Int16 interleaved
        let pcm = data.dropFirst(12)
        guard !pcm.isEmpty else { return }

        // Drop excess if ring buffer getting full (network burst protection)
        if ringBuffer.available > 48 {
            _ = ringBuffer.pop()
        }
        ringBuffer.push(Data(pcm))
    }

    // MARK: High-Priority Render Thread

    private func startRenderThread() {
        renderRunning = true
        renderThread = Thread {
            // Boost this thread to audio priority
            Thread.current.threadPriority = 1.0
            self.renderLoop()
        }
        renderThread?.qualityOfService = .userInteractive
        renderThread?.start()
    }

    private func renderLoop() {
        // 10 ms sleep = 480 samples @ 48kHz
        let sleepNs: UInt64 = 10_000_000

        while renderRunning {
            let available = ringBuffer.available

            // Update latency display every ~200ms
            if Int.random(in: 0..<20) == 0 {
                let ms = max(0, (available - 1) * 10)
                DispatchQueue.main.async { self.latencyMs = ms }
            }

            if let pcmData = ringBuffer.pop() {
                scheduleFrame(from: pcmData)
            } else {
                // Underrun: schedule silence to keep player clock running (no click)
                scheduleFrame(silence: true)
            }

            Thread.sleep(forTimeInterval: 0.0095)   // ~9.5ms to stay ahead
        }
    }

    private func scheduleFrame(from pcmData: Data? = nil, silence: Bool = false) {
        let count = Int(frameCapacity)

        guard let buf = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: frameCapacity) else { return }
        buf.frameLength = frameCapacity

        guard let lCh = buf.floatChannelData?[0],
              let rCh = buf.floatChannelData?[1] else { return }

        if silence || pcmData == nil {
            memset(lCh, 0, count * MemoryLayout<Float>.stride)
            memset(rCh, 0, count * MemoryLayout<Float>.stride)
        } else {
            let frames = min(pcmData!.count / 4, count)
            pcmData!.withUnsafeBytes { raw in
                guard let int16Ptr = raw.bindMemory(to: Int16.self).baseAddress else { return }
                for i in 0..<frames {
                    lCh[i] = Float(int16Ptr[i * 2])     / 32768.0
                    rCh[i] = Float(int16Ptr[i * 2 + 1]) / 32768.0
                }
                if frames < count {
                    for i in frames..<count { lCh[i] = 0; rCh[i] = 0 }
                }
            }
        }

        player.scheduleBuffer(buf, completionHandler: nil)

        if !player.isPlaying {
            player.play()
        }
    }

    // MARK: USB command channel

    func sendUSBCommand(_ cmd: String) {
        activeTCPConnection?.send(content: cmd.data(using: .utf8),
                                  completion: .contentProcessed { _ in })
    }

    // MARK: Public

    func setVolume(_ volume: Float) { player.volume = volume }

    func reset() {
        player.stop()
        while ringBuffer.pop() != nil {}    // flush ring buffer
        isUSBConnected = false
        activeTCPConnection?.cancel()
        activeTCPConnection = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.player.play()
        }
    }

    // MARK: Notifications

    @objc private func handleEngineChange(_: Notification) { restartEngine() }
    @objc private func handleRouteChange(_: Notification) {
        // Reconnect session (Bluetooth / AirPods switch)
        do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
        restartEngine()
    }

    private func restartEngine() {
        do {
            engine.prepare()
            try engine.start()
            if !player.isPlaying { player.play() }
        } catch { print("Engine restart error: \(error)") }
    }
}
