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
    
    private var isPlaying = false
    private let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: true)!
    private let floatFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
    private let converter: AVAudioConverter
    
    init() {
        converter = AVAudioConverter(from: audioFormat, to: floatFormat)!
        setupEngine()
        setupAudioSession()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleConfigurationChange), name: .AVAudioEngineConfigurationChange, object: engine)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        
        // Start listening automatically on launch for both USB and Wi-Fi
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
            tcpListener = try NWListener(using: params, on: 5002)
            tcpListener?.newConnectionHandler = { [weak self] newConnection in
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
            print("Failed to start TCP listener for USB: \(error)")
        }
    }
    
    private func readTCPPacket(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] (lengthData, _, isComplete, error) in
            guard let self = self, let lengthData = lengthData, lengthData.count == 4, error == nil else {
                DispatchQueue.main.async {
                    self?.isUSBConnected = false
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
    
    private func processPacket(_ data: Data) {
        // Packet: Seq(4) + TS(8) + PCM(1920)
        let pcmData = data.dropFirst(12)
        
        let frameCapacity = AVAudioFrameCount(pcmData.count / 4) // 2 channels * 2 bytes = 4 bytes per frame
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCapacity) else { return }
        pcmBuffer.frameLength = frameCapacity
        
        pcmData.withUnsafeBytes { rawBufferPointer in
            guard let source = rawBufferPointer.bindMemory(to: Int16.self).baseAddress else { return }
            let dest = pcmBuffer.int16ChannelData![0]
            memcpy(dest, source, pcmData.count)
        }
        
        guard let floatBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: frameCapacity) else { return }
        
        var error: NSError? = nil
        converter.convert(to: floatBuffer, error: &error, withInputFrom: { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        })
        
        if error == nil {
            scheduleBuffer(floatBuffer)
        }
    }
    
    private var queuedBuffers = 0
    
    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        queuedBuffers += 1
        
        DispatchQueue.main.async {
            self.latencyMs = self.queuedBuffers * 10
        }
        
        if queuedBuffers > 5 {
            queuedBuffers -= 1
            return
        }
        
        player.scheduleBuffer(buffer) {
            DispatchQueue.main.async {
                self.queuedBuffers -= 1
            }
        }
        
        if !player.isPlaying {
            player.play()
        }
    }
    
    func setVolume(_ volume: Float) {
        player.volume = volume
    }
}
