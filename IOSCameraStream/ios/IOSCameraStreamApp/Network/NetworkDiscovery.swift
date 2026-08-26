import Foundation
import Network
import Combine

struct DiscoveredPC: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let ip: String
    let tcpPort: Int
    let udpPort: Int
}

class NetworkDiscovery: ObservableObject {
    static let shared = NetworkDiscovery()

    @Published var discoveredPCs: [DiscoveredPC] = []
    @Published var isSearching: Bool = false

    private var broadcastConn: NWConnection?
    private var listenConn: NWConnection?
    private var pingTimer: Timer?
    private let discoveryQueue = DispatchQueue(label: "com.bonaycamera.discovery", qos: .utility)

    init() {
        startDiscovery()
    }

    func startDiscovery() {
        isSearching = true
        sendBroadcast()
        startPingTimer()
    }

    func stopDiscovery() {
        isSearching = false
        pingTimer?.invalidate()
        pingTimer = nil
        broadcastConn?.cancel()
        broadcastConn = nil
    }

    private func sendBroadcast() {
        let host = NWEndpoint.Host("255.255.255.255")
        let port = NWEndpoint.Port(integerLiteral: 5005)

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let conn = NWConnection(host: host, port: port, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            if state == .ready {
                let msg = "DISCOVER_CAMERA".data(using: .utf8)!
                conn.send(content: msg, completion: .contentProcessed { _ in })
                self?.receiveResponses(conn)
            }
        }
        conn.start(queue: discoveryQueue)
        broadcastConn = conn
    }

    private func receiveResponses(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else { return }
            if let str = String(data: data, encoding: .utf8) {
                self.handleDiscoveryResponse(str)
            }
            self.receiveResponses(conn)
        }
    }

    private func handleDiscoveryResponse(_ msg: String) {
        // format: BONAY_CAMERA_PC|name|tcpPort|udpPort
        let parts = msg.split(separator: "|").map(String.init)
        guard parts.count >= 4, parts[0] == "BONAY_CAMERA_PC" else { return }

        let name = parts[1]
        let tcpPort = Int(parts[2]) ?? 5003
        let udpPort = Int(parts[3]) ?? 5004

        // Extract IP if possible or match discovered
        DispatchQueue.main.async {
            if !self.discoveredPCs.contains(where: { $0.name == name }) {
                let pc = DiscoveredPC(name: name, ip: "", tcpPort: tcpPort, udpPort: udpPort)
                self.discoveredPCs.append(pc)
            }
        }
    }

    private func startPingTimer() {
        DispatchQueue.main.async {
            self.pingTimer?.invalidate()
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.sendBroadcast()
            }
        }
    }

    func connect(to pc: DiscoveredPC) {
        VideoSender.shared.connectToPC(ip: pc.ip, pcName: pc.name)
    }

    func connect(toIP ip: String, pcName: String = "PC") {
        VideoSender.shared.connectToPC(ip: ip, pcName: pcName)
    }
}
