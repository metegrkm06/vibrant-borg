import Foundation
import Network
import AVFoundation

class AudioEngine: ObservableObject {
    static let shared = AudioEngine()
    
    @Published var latencyMs: Int = 0
    @Published var isUSBConnected: Bool = false
    
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    
    private var udpListener: NWListener?
    private var tcpListener: NWListener?
    private var activeTCPConnection: NWConnection?
    
    private let floatFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
    
    init() {
        setupEngine()
        setupAudioSession()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleConfigurationChange), name: .AVAudioEngineConfigurationChange, object: engine)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        
        startListening()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("AudioSession setup error: \(error)")
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        restartEngine()
    }
    
    @objc private func handleConfigurationChange(notification: Notification) {
        restartEngine()
    }
    
    private func restartEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true)
            engine.prepare()
            try engine.start()
            if !player.isPlaying {
                player.play()
            }
        } catch {
            print("Failed to restart engine: \(error)")
        }
    }
    
    private func setupEngine() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: floatFormat)
        
        do {
            try engine.start()
        } catch {
            print("Engine start error: \(error)")
        }
    }
    
    func startListening() {
        startUDPListener()
        startTCPListener()
    }
    
    private func startUDPListener() {
        guard udpListener == nil else { return }
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            udpListener = try NWListener(using: params, on: 5000)
            udpListener?.newConnectionHandler = { [weak self] newConnection in
                newConnection.start(queue: .global(qos: .userInteractive))
                self?.receiveUDP(on: newConnection)
            }
            udpListener?.start(queue: .global(qos: .userInteractive))
        } catch {
            print("Failed to start UDP listener: \(error)")
        }
    }
    
    private func receiveUDP(on connection: NWConnection) {
        connection.receiveMessage { [weak self] (content, context, isComplete, error) in
            guard let self = self else { return }
            if let data = content, data.count > 12 {
                self.processPacket(data)
            }
            if error == nil {
                self.receiveUDP(on: connection)
            }
        }
    }
    
    private func startTCPListener() {
        guard tcpListener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            tcpListener = try NWListener(using: params, on: 5002)
            tcpListener?.newConnectionHandler = { [weak self] newConnection in
                self?.activeTCPConnection = newConnection
                newConnection.start(queue: .global(qos: .userInteractive))
                DispatchQueue.main.async {
                    self?.isUSBConnected = true
                    NetworkListener.shared.isConnected = true
                    NetworkListener.shared.pcName = "PC (Direct USB Cable)"
                }
                self?.readTCPPacket(on: newConnection)
            }
            tcpListener?.start(queue: .global(qos: .userInteractive))
        } catch {
            print("Failed to start TCP listener: \(error)")
        }
    }
    
    private func readTCPPacket(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] (lengthData, _, isComplete, error) in
            guard let self = self, let lengthData = lengthData, lengthData.count == 4, error == nil else {
                DispatchQueue.main.async {
                    self?.isUSBConnected = false
                    if self?.activeTCPConnection === connection {
                        self?.activeTCPConnection = nil
                    }
                }
                return
            }
            
            let packetLength = Int(lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            guard packetLength > 0 && packetLength < 65536 else { return }
            
            self.readTCPExact(on: connection, count: packetLength, accumulated: Data()) { [weak self] packetData in
                if let packetData = packetData, packetData.count > 12 {
                    self?.processPacket(packetData)
                }
                self?.readTCPPacket(on: connection)
            }
        }
    }
    
    private func readTCPExact(on connection: NWConnection, count: Int, accumulated: Data, completion: @escaping (Data?) -> Void) {
        let needed = count - accumulated.count
        guard needed > 0 else {
            completion(accumulated)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: needed) { [weak self] (content, _, isComplete, error) in
            guard let content = content, error == nil else {
                completion(nil)
                return
            }
            var newAcc = accumulated
            newAcc.append(content)
            if newAcc.count == count {
                completion(newAcc)
            } else {
                self?.readTCPExact(on: connection, count: count, accumulated: newAcc, completion: completion)
            }
        }
    }
    
    func sendUSBCommand(_ cmd: String) {
        if let connection = activeTCPConnection {
            let data = cmd.data(using: .utf8)
            connection.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }
    
    private func processPacket(_ data: Data) {
        // Packet: Seq(4 bytes) + Timestamp(8 bytes) + PCM Int16 Stereo(N bytes)
        let pcmData = data.dropFirst(12)
        let frameCount = AVAudioFrameCount(pcmData.count / 4) // 2 channels * 2 bytes = 4 bytes per frame
        guard frameCount > 0 else { return }
        
        guard let floatBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: frameCount) else { return }
        floatBuffer.frameLength = frameCount
        
        guard let leftChannel = floatBuffer.floatChannelData?[0],
              let rightChannel = floatBuffer.floatChannelData?[1] else { return }
        
        // Fast direct linear de-interleaving and float conversion (eliminates converter filter distortion)
        pcmData.withUnsafeBytes { rawBufferPointer in
            guard let int16Ptr = rawBufferPointer.bindMemory(to: Int16.self).baseAddress else { return }
            let count = Int(frameCount)
            for i in 0..<count {
                leftChannel[i] = Float(int16Ptr[i * 2]) / 32768.0
                rightChannel[i] = Float(int16Ptr[i * 2 + 1]) / 32768.0
            }
        }
        
        scheduleBuffer(floatBuffer)
    }
    
    private var queuedBuffers = 0
    
    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        queuedBuffers += 1
        
        DispatchQueue.main.async {
            self.latencyMs = self.queuedBuffers * 20
        }
        
        // Smooth jitter buffer: prevent latency buildup without clicking
        if queuedBuffers > 8 {
            queuedBuffers -= 1
            return
        }
        
        player.scheduleBuffer(buffer) {
            DispatchQueue.main.async {
                self.queuedBuffers = max(0, self.queuedBuffers - 1)
            }
        }
        
        if !player.isPlaying {
            player.play()
        }
    }
    
    func setVolume(_ volume: Float) {
        player.volume = volume
    }
    
    func reset() {
        player.stop()
        queuedBuffers = 0
        isUSBConnected = false
        activeTCPConnection?.cancel()
        activeTCPConnection = nil
        player.play()
    }
}
