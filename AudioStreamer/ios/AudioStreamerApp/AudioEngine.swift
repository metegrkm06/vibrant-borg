import Foundation
import Network
import AVFoundation

// ─── Circular sample buffer (thread-safe, Float32 interleaved stereo) ───────
final class SampleRingBuffer {
    private var buf: [Float]
    private let cap: Int
    private var writePos: Int = 0
    private var readPos: Int  = 0
    private var count: Int    = 0
    private let lock = NSLock()

    init(seconds: Double = 0.5, sampleRate: Int = 48000, channels: Int = 2) {
        cap = Int(Double(sampleRate) * seconds) * channels
        buf = Array(repeating: 0, count: cap)
    }

    var available: Int { lock.lock(); defer { lock.unlock() }; return count }

    func push(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        for s in samples {
            buf[writePos] = s
            writePos = (writePos + 1) % cap
            if count < cap { count += 1 }
            else { readPos = (readPos + 1) % cap } // overwrite oldest
        }
    }

    // fills `out` with `needed` floats; returns true if fully satisfied
    @discardableResult
    func pull(into out: UnsafeMutablePointer<Float>, count needed: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let have = min(needed, count)
        for i in 0..<have {
            out[i] = buf[readPos]
            readPos = (readPos + 1) % cap
        }
        count -= have
        if have < needed {
            // underrun: fill rest with silence
            memset(out + have, 0, (needed - have) * MemoryLayout<Float>.stride)
            return false
        }
        return true
    }
}

// ─── AudioEngine ─────────────────────────────────────────────────────────────
class AudioEngine: ObservableObject {
    static let shared = AudioEngine()

    @Published var latencyMs: Int = 0
    @Published var isUSBConnected: Bool = false

    private let engine      = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private var udpListener: NWListener?
    private var tcpListener: NWListener?
    private var activeTCPConnection: NWConnection?

    private let sampleRate: Double = 48000
    private let channels:   Int    = 2
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000, channels: 2, interleaved: true)!

    private let ring = SampleRingBuffer(seconds: 0.15) // 150ms max buffer
    private var frameCounter = 0

    init() {
        setupSession()
        setupEngine()

        NotificationCenter.default.addObserver(self, selector: #selector(handleEngineChange),
            name: .AVAudioEngineConfigurationChange, object: engine)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification, object: nil)

        startListeners()
    }

    // MARK: - Session

    private func setupSession() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default,
                              options: [.allowBluetoothA2DP, .allowAirPlay])
            try s.setPreferredIOBufferDuration(0.005)
            try s.setActive(true)
        } catch { print("Session error: \(error)") }
    }

    // MARK: - Engine (pull-based via AVAudioSourceNode)

    private func setupEngine() {
        // AVAudioSourceNode calls this render block whenever the engine needs audio.
        // No scheduling, no queue — just pull from the ring buffer RIGHT NOW.
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, abl -> OSStatus in
            guard let self else { return noErr }
            let needed = Int(frameCount) * self.channels
            // abl has one buffer (interleaved stereo Float32)
            if let ptr = abl.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) {
                self.ring.pull(into: ptr, count: needed)
            }
            // Update latency display every ~200 render calls
            self.frameCounter += 1
            if self.frameCounter % 200 == 0 {
                let ms = (self.ring.available / self.channels) * 1000 / Int(self.sampleRate)
                DispatchQueue.main.async { self.latencyMs = ms }
            }
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch { print("Engine start error: \(error)") }
    }

    // MARK: - Packet ingestion

    private func ingestPacket(_ data: Data) {
        // Header: Seq(4) + Timestamp(8) = 12 bytes, rest is Int16 interleaved stereo PCM
        guard data.count > 12 else { return }
        let pcm = data.dropFirst(12)
        let numSamples = pcm.count / 2 // each Int16 = 1 sample

        var floats = [Float](repeating: 0, count: numSamples)
        pcm.withUnsafeBytes { raw in
            guard let p = raw.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<numSamples {
                floats[i] = Float(p[i]) / 32768.0
            }
        }
        ring.push(floats)
    }

    // MARK: - Listeners

    private func startListeners() {
        // UDP (Wi-Fi)
        let udpParams = NWParameters.udp
        udpParams.allowLocalEndpointReuse = true
        if let l = try? NWListener(using: udpParams, on: 5000) {
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global(qos: .userInteractive))
                self?.recvUDP(conn)
            }
            l.start(queue: .global(qos: .userInteractive))
            udpListener = l
        }

        // TCP (USB cable)
        let tcpParams = NWParameters.tcp
        tcpParams.allowLocalEndpointReuse = true
        if let l = try? NWListener(using: tcpParams, on: 5002) {
            l.newConnectionHandler = { [weak self] conn in
                self?.activeTCPConnection = conn
                conn.start(queue: .global(qos: .userInteractive))
                DispatchQueue.main.async {
                    self?.isUSBConnected = true
                    NetworkListener.shared.isConnected = true
                    NetworkListener.shared.pcName = "PC (Direct USB Cable)"
                }
                self?.recvTCPLength(conn)
            }
            l.start(queue: .global(qos: .userInteractive))
            tcpListener = l
        }
    }

    private func recvUDP(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, err in
            if let data { self?.ingestPacket(data) }
            if err == nil { self?.recvUDP(conn) }
        }
    }

    private func recvTCPLength(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, err in
            guard let self, let data, data.count == 4, err == nil else {
                DispatchQueue.main.async {
                    self?.isUSBConnected = false
                    self?.activeTCPConnection = nil
                }
                return
            }
            let len = Int(data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            guard len > 12, len < 65536 else { self.recvTCPLength(conn); return }
            self.recvTCPBody(conn, remaining: len, acc: Data())
        }
    }

    private func recvTCPBody(_ conn: NWConnection, remaining: Int, acc: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, _, err in
            guard let self, let data, err == nil else { return }
            var newAcc = acc; newAcc.append(data)
            if newAcc.count >= remaining {
                self.ingestPacket(newAcc)
                self.recvTCPLength(conn)
            } else {
                self.recvTCPBody(conn, remaining: remaining - data.count, acc: newAcc)
            }
        }
    }

    // MARK: - USB command send

    func sendUSBCommand(_ cmd: String) {
        activeTCPConnection?.send(content: cmd.data(using: .utf8),
                                  completion: .contentProcessed { _ in })
    }

    // MARK: - Public

    func setVolume(_ v: Float) { engine.mainMixerNode.outputVolume = v }

    func reset() {
        // Drain ring buffer
        _ = ring.available // just flush conceptually — new data overwrites
        isUSBConnected = false
        activeTCPConnection?.cancel()
        activeTCPConnection = nil
    }

    // MARK: - Notifications

    @objc private func handleEngineChange(_: Notification) { restartEngine() }
    @objc private func handleRouteChange(_: Notification) {
        try? AVAudioSession.sharedInstance().setActive(true)
        restartEngine()
    }

    private func restartEngine() {
        do { engine.prepare(); try engine.start() }
        catch { print("Engine restart error: \(error)") }
    }
}
