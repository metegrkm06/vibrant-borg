import Foundation
import Network
import Combine

class VideoSender: ObservableObject {
    static let shared = VideoSender()

    @Published var isConnected: Bool = false
    @Published var isUSBMode: Bool = false
    @Published var connectedPCName: String = "PC"
    @Published var latencyMs: Int = 0

    private var tcpListener: NWListener?
    private var activeTCPConnection: NWConnection?
    private var udpConnection: NWConnection?
    private var targetIP: String?
    private let sendQueue = DispatchQueue(label: "com.bonaycamera.sendQueue", qos: .userInteractive)

    // Backlog Protection: ensures zero delay by dropping intermediate frames if sender is busy
    private var isSendingFrame = false
    private let sendLock = NSLock()

    init() {
        startTCPListener()
        setupFrameEncodingHook()
    }

    // ─── Direct USB Cable Mode & Wi-Fi TCP Listener (Port 5003) ────────────────

    func startTCPListener() {
        guard tcpListener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        do {
            tcpListener = try NWListener(using: params, on: 5003)
            tcpListener?.newConnectionHandler = { [weak self] conn in
                self?.handleIncomingTCP(conn)
            }
            tcpListener?.start(queue: .global(qos: .userInteractive))
        } catch {
            print("Failed to start TCP listener on port 5003: \(error)")
        }
    }

    private func handleIncomingTCP(_ conn: NWConnection) {
        activeTCPConnection?.cancel()
        activeTCPConnection = conn

        conn.start(queue: sendQueue)

        // Default to Wi-Fi until handshake verifies USB
        DispatchQueue.main.async {
            self.isConnected = true
            self.isUSBMode = false
            self.connectedPCName = "PC"
            CameraManager.shared.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }

        readIncomingCommands(conn)
    }

    // ─── Wi-Fi Mode (Connects to PC IP:5003 via TCP and UDP:5004) ───────────────

    func connectToPC(ip: String, pcName: String) {
        targetIP = ip
        let host = NWEndpoint.Host(ip)
        let tcpPort = NWEndpoint.Port(integerLiteral: 5003)
        let udpPort = NWEndpoint.Port(integerLiteral: 5004)

        // TCP Connection for reliable stream & control
        let tcpConn = NWConnection(host: host, port: tcpPort, using: .tcp)
        tcpConn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self?.isConnected = true
                    self?.isUSBMode = false
                    self?.connectedPCName = pcName
                    CameraManager.shared.start()
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                // Send Wi-Fi handshake
                let handshake = "CMD|HANDSHAKE|WIFI|\(UIDevice.current.name)\n".data(using: .utf8)!
                tcpConn.send(content: handshake, completion: .contentProcessed { _ in })
                self?.readIncomingCommands(tcpConn)
            case .failed(let err):
                print("TCP connection failed: \(err)")
                self?.disconnect()
            default:
                break
            }
        }
        tcpConn.start(queue: sendQueue)
        activeTCPConnection = tcpConn

        // UDP Connection for Wi-Fi high-speed transmission
        let udpConn = NWConnection(host: host, port: udpPort, using: .udp)
        udpConn.start(queue: sendQueue)
        self.udpConnection = udpConn
    }

    func disconnect() {
        activeTCPConnection?.cancel()
        activeTCPConnection = nil
        udpConnection?.cancel()
        udpConnection = nil

        DispatchQueue.main.async {
            self.isConnected = false
            self.isUSBMode = false
            self.connectedPCName = "PC"
        }
    }

    // ─── Zero-Delay Frame Transmission (Backlog-Free) ─────────────────────────

    private func setupFrameEncodingHook() {
        CameraManager.shared.onFrameEncoded = { [weak self] jpegData, tsNs in
            guard let self = self, self.isConnected else { return }
            self.sendFrame(jpegData, timestampNs: tsNs)
        }
    }

    private func sendFrame(_ data: Data, timestampNs: UInt64) {
        sendLock.lock()
        if isSendingFrame {
            // Drop late frame immediately to prevent queuing lag
            sendLock.unlock()
            return
        }
        isSendingFrame = true
        sendLock.unlock()

        // Packet Header: [Magic 4B: 'BNCF'][Length 4B: BigEndian][TimestampNs 8B: BigEndian]
        let magic = "BNCF".data(using: .utf8)!
        var length = UInt32(data.count).bigEndian
        var ts = timestampNs.bigEndian

        var header = Data()
        header.append(magic)
        header.append(Data(bytes: &length, count: 4))
        header.append(Data(bytes: &ts, count: 8))

        let fullPacket = header + data

        // 1. If USB or TCP active: stream full packet over TCP
        if let tcp = activeTCPConnection {
            tcp.send(content: fullPacket, completion: .contentProcessed { [weak self] _ in
                self?.sendLock.lock()
                self?.isSendingFrame = false
                self?.sendLock.unlock()
            })
            return
        }

        // 2. If Wi-Fi UDP active: send fragmented packets
        if let udp = udpConnection {
            sendUDPFragments(data, timestampNs: timestampNs, over: udp)
            sendLock.lock()
            isSendingFrame = false
            sendLock.unlock()
        } else {
            sendLock.lock()
            isSendingFrame = false
            sendLock.unlock()
        }
    }

    private func sendUDPFragments(_ data: Data, timestampNs: UInt64, over conn: NWConnection) {
        let chunkSize = 60000 // fit within 65535 UDP MTU
        let totalFrags = UInt16((data.count + chunkSize - 1) / chunkSize)
        let seq = UInt32.random(in: 0...UInt32.max)
        let magic = "BNCU".data(using: .utf8)!

        for i in 0..<totalFrags {
            let start = Int(i) * chunkSize
            let end = min(start + chunkSize, data.count)
            let chunk = data.subdata(in: start..<end)

            var seqBE = seq.bigEndian
            var fragIdxBE = i.bigEndian
            var fragTotalBE = totalFrags.bigEndian
            var tsBE = timestampNs.bigEndian

            var header = Data()
            header.append(magic)
            header.append(Data(bytes: &seqBE, count: 4))
            header.append(Data(bytes: &fragIdxBE, count: 2))
            header.append(Data(bytes: &fragTotalBE, count: 2))
            header.append(Data(bytes: &tsBE, count: 8))

            let packet = header + chunk
            conn.send(content: packet, completion: .contentProcessed { _ in })
        }
    }

    // ─── Incoming Remote Commands from PC ─────────────────────────────────────

    private func readIncomingCommands(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else { return }
            if let cmdStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                for line in cmdStr.components(separatedBy: "\n") {
                    self.executeRemoteCommand(line)
                }
            }
            self.readIncomingCommands(conn)
        }
    }

    private func executeRemoteCommand(_ cmd: String) {
        let parts = cmd.split(separator: "|").map(String.init)
        guard parts.count >= 2, parts[0] == "CMD" else { return }

        let action = parts[1]
        DispatchQueue.main.async {
            switch action {
            case "HANDSHAKE":
                if parts.count > 2 {
                    if parts[2] == "USB" {
                        self.isUSBMode = true
                        self.connectedPCName = "PC (Direct USB Cable)"
                    } else if parts[2] == "WIFI" {
                        self.isUSBMode = false
                        self.connectedPCName = parts.count > 3 ? parts[3] : "PC (Wi-Fi)"
                    }
                }
            case "CAM":
                if parts.count > 2 {
                    let camType = parts[2]
                    switch camType {
                    case "FRONT": CameraManager.shared.switchCamera(to: .front)
                    case "BACK_WIDE": CameraManager.shared.switchCamera(to: .backWide)
                    case "BACK_ULTRA_WIDE": CameraManager.shared.switchCamera(to: .backUltraWide)
                    case "BACK_TELE": CameraManager.shared.switchCamera(to: .backTelephoto)
                    default: break
                    }
                }
            case "TORCH":
                if parts.count > 2 {
                    let on = parts[2] == "ON"
                    CameraManager.shared.toggleTorch(on: on)
                }
            case "FPS":
                if parts.count > 2, let fps = Int(parts[2]) {
                    CameraManager.shared.setFPS(fps)
                }
            case "QUALITY":
                if parts.count > 2 {
                    switch parts[2] {
                    case "1080P": CameraManager.shared.setResolution(.p1080)
                    case "720P":  CameraManager.shared.setResolution(.p720)
                    case "480P":  CameraManager.shared.setResolution(.p480)
                    case "4K":    CameraManager.shared.setResolution(.p4k)
                    default: break
                    }
                }
            case "ZOOM":
                if parts.count > 2, let zoomVal = Double(parts[2]) {
                    CameraManager.shared.setZoom(CGFloat(zoomVal))
                }
            case "MIRROR":
                CameraManager.shared.toggleMirror()
            case "ROTATE":
                if parts.count > 2 && parts[2] == "RESET" {
                    CameraManager.shared.resetRotation()
                } else {
                    CameraManager.shared.cycleRotation()
                }
            case "EXPOSURE":
                if parts.count > 2, let bias = Float(parts[2]) {
                    CameraManager.shared.setExposureBias(bias)
                }
            default:
                break
            }
        }
    }
}
