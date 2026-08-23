import Foundation
import Network
import AVFoundation

class AudioEngine: ObservableObject {
    static let shared = AudioEngine()
    
    @Published var latencyMs: Int = 0
    
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    
    private var listener: NWListener?
    private var connection: NWConnection?
    
    private var isPlaying = false
    private let audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: true)!
    
    // To convert Int16 interleaved to Float32 non-interleaved if needed by AVAudioEngine
    private let floatFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
    private let converter: AVAudioConverter
    
    init() {
        converter = AVAudioConverter(from: audioFormat, to: floatFormat)!
        setupEngine()
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
        guard listener == nil else { return }
        
        do {
            let params = NWParameters.udp
            listener = try NWListener(using: params, on: 5000)
            
            listener?.newConnectionHandler = { [weak self] newConnection in
                self?.connection = newConnection
                newConnection.start(queue: .global(qos: .userInteractive))
                self?.receiveLoop(on: newConnection)
            }
            
            listener?.start(queue: .global(qos: .userInteractive))
        } catch {
            print("Failed to start listener: \(error)")
        }
    }
    
    private func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] (content, context, isComplete, error) in
            guard let self = self else { return }
            
            if let data = content, data.count > 12 {
                self.processPacket(data)
            }
            
            if error == nil {
                self.receiveLoop(on: connection)
            }
        }
    }
    
    private func processPacket(_ data: Data) {
        // Packet: Seq(4) + TS(8) + PCM(1920)
        let pcmData = data.dropFirst(12)
        
        let frameCapacity = AVAudioFrameCount(pcmData.count / 4) // 2 channels * 2 bytes = 4 bytes per frame
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCapacity) else { return }
        pcmBuffer.frameLength = frameCapacity
        
        // Copy data to buffer
        pcmData.withUnsafeBytes { rawBufferPointer in
            guard let source = rawBufferPointer.bindMemory(to: Int16.self).baseAddress else { return }
            let dest = pcmBuffer.int16ChannelData![0]
            // Interleaved data is essentially just copied into the first channel array (which represents the whole interleaved block in CoreAudio if configured so, wait - standard format is float non-interleaved. We specified interleaved: true for audioFormat!)
            // Actually, CoreAudio expects data in a specific way for interleaved.
            memcpy(dest, source, pcmData.count)
        }
        
        // Convert to Float32 non-interleaved for engine
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
        
        // Drop packet if falling too far behind (e.g. > 50ms latency)
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
