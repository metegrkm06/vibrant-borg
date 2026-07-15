import Foundation
import Combine
import AVFoundation

struct VDSVideo: Identifiable, Codable {
    var id: String { filename }
    let filename: String
    let sizeBytes: Int64
    let createdAt: String
}

class VDSNetworkManager: ObservableObject {
    @Published var vdsIP: String = UserDefaults.standard.string(forKey: "vdsIP") ?? "" {
        didSet { UserDefaults.standard.set(vdsIP, forKey: "vdsIP") }
    }
    @Published var vdsPort: String = UserDefaults.standard.string(forKey: "vdsPort") ?? "3000" {
        didSet { UserDefaults.standard.set(vdsPort, forKey: "vdsPort") }
    }
    @Published var secretToken: String = UserDefaults.standard.string(forKey: "vdsSecretToken") ?? "" {
        didSet { UserDefaults.standard.set(secretToken, forKey: "vdsSecretToken") }
    }
    
    @Published var remoteVideos: [VDSVideo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isDownloading = false

    var isConfigured: Bool {
        return !vdsIP.isEmpty && !secretToken.isEmpty
    }

    private var baseURL: String {
        return "http://\(vdsIP):\(vdsPort)"
    }
    
    func fetchVideos() {
        guard isConfigured else {
            errorMessage = "Please enter VDS IP and Secret Token"
            return
        }
        
        guard let url = URL(string: "\(baseURL)/videos") else {
            errorMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(secretToken, forHTTPHeaderField: "x-secret-token")
        
        isLoading = true
        errorMessage = nil
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                    self?.errorMessage = "Unauthorized: Invalid Secret Token"
                    return
                }
                
                do {
                    let result = try JSONDecoder().decode([String: [VDSVideo]].self, from: data)
                    self?.remoteVideos = result["videos"] ?? []
                } catch {
                    self?.errorMessage = "Failed to parse videos: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func getStreamAsset(for video: VDSVideo) -> AVURLAsset? {
        guard let url = URL(string: "\(baseURL)/download/\(video.filename)") else { return nil }
        let options = ["AVURLAssetHTTPHeaderFieldsKey": ["x-secret-token": secretToken]]
        return AVURLAsset(url: url, options: options)
    }

    func downloadVideo(_ video: VDSVideo, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/download/\(video.filename)") else { return }
        
        var request = URLRequest(url: url)
        request.setValue(secretToken, forHTTPHeaderField: "x-secret-token")
        
        isDownloading = true
        
        URLSession.shared.downloadTask(with: request) { [weak self] localURL, response, error in
            DispatchQueue.main.async {
                self?.isDownloading = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    completion(false)
                    return
                }
                
                guard let localURL = localURL else {
                    completion(false)
                    return
                }
                
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsPath.appendingPathComponent(video.filename)
                
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: localURL, to: destinationURL)
                    completion(true)
                } catch {
                    self?.errorMessage = "Failed to save video: \(error.localizedDescription)"
                    completion(false)
                }
            }
        }.resume()
    }
}
