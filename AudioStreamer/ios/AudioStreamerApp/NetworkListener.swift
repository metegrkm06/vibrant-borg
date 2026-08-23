import Foundation
import Network
import UIKit

class NetworkListener: ObservableObject {
    static let shared = NetworkListener()
    
    @Published var isConnected = false
    @Published var pcName = "Looking for PC..."
    @Published var targetIP: String? = nil
    
    private var discoveryConnection: NWConnection?
    private var discoveryTimer: Timer?
    private var pingTimer: Timer?
    
    private let discoveryPort: NWEndpoint.Port = 5001
    private let deviceName = UIDevice.current.name
    
    init() {
        startDiscovery()
    }
    
    func startDiscovery() {
        // We broadcast to 255.255.255.255 on port 5001
        let host = NWEndpoint.Host("255.255.255.255")
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        
        discoveryConnection = NWConnection(host: host, port: discoveryPort, using: params)
        discoveryConnection?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.beginReceiving()
                self.startDiscoveryTimer()
            default:
                break
            }
        }
        discoveryConnection?.start(queue: .global())
    }
    
    private func startDiscoveryTimer() {
        DispatchQueue.main.async {
            self.discoveryTimer?.invalidate()
            self.discoveryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self, !self.isConnected else { return }
                self.sendUDP(message: "DISCOVER", to: self.discoveryConnection)
            }
        }
    }
    
    private func beginReceiving() {
        discoveryConnection?.receiveMessage { [weak self] (content, context, isComplete, error) in
            guard let self = self else { return }
            if let data = content, let message = String(data: data, encoding: .utf8) {
                if message.hasPrefix("AUDIOSTREAMER_PC|") {
                    let parts = message.components(separatedBy: "|")
                    if parts.count >= 3 {
                        let name = parts[1]
                        let ipAddress = parts[2]
                        DispatchQueue.main.async {
                            self.connectToPC(ip: ipAddress, name: name)
                        }
                    }
                }
            }
            if error == nil {
                self.beginReceiving()
            }
        }
    }
    
    func connectToPC(ip: String, name: String) {
        guard !isConnected else { return }
        
        self.isConnected = true
        self.pcName = name
        self.targetIP = ip
        self.discoveryTimer?.invalidate()
        
        // Setup direct connection for PINGs
        let host = NWEndpoint.Host(ip)
        let params = NWParameters.udp
        let connection = NWConnection(host: host, port: discoveryPort, using: params)
        connection.start(queue: .global())
        
        self.sendUDP(message: "CONNECT|\(self.deviceName)", to: connection)
        
        DispatchQueue.main.async {
            self.pingTimer?.invalidate()
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.sendUDP(message: "PING", to: connection)
            }
        }
        
        AudioEngine.shared.startListening()
    }
    
    private func sendUDP(message: String, to connection: NWConnection?) {
        let data = message.data(using: .utf8)
        connection?.send(content: data, completion: .contentProcessed({ error in
            // Handle error if needed
        }))
    }
    
}
