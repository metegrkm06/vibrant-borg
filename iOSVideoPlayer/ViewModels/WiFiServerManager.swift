import Foundation
import Swifter

// For networking structures and functions (getifaddrs)
#if canImport(Darwin)
import Darwin
#endif

class WiFiServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var serverIP: String?
    @Published var serverPort: UInt16 = 8080
    
    private var server: HttpServer?
    
    var serverURL: String? {
        guard let ip = serverIP else { return nil }
        return "http://\(ip):\(serverPort)"
    }
    
    // Starts the local Swifter HTTP server
    func startServer() {
        guard !isRunning else { return }
        
        let server = HttpServer()
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Root Portal page
        server["/"] = { _ in
            return .ok(.html(self.portalHTML()))
        }
        
        // JSON API Endpoint to list available videos
        server["/list"] = { _ in
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: documentsURL,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
                let videos = fileURLs.filter { url in
                    let ext = url.pathExtension.lowercased()
                    return ext == "mp4" || ext == "mov"
                }
                
                var list: [[String: String]] = []
                for url in videos {
                    let name = url.lastPathComponent
                    let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
                    let size = resourceValues?.fileSize ?? 0
                    list.append([
                        "name": name,
                        "size": ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                    ])
                }
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: list, options: []),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    return .ok(.text(jsonStr))
                }
            } catch {
                print("Error building file list: \(error)")
            }
            return .internalServerError
        }
        
        // Expose directory path using Swifter's native folder sharer
        server["/files/:path"] = shareFilesFromDirectory(documentsURL.path)
        
        // Multipart POST request to handle video uploads
        server.POST["/upload"] = { request in
            let multipart = request.parseMultiPartFormData()
            for part in multipart {
                if let fileName = part.fileName, !fileName.isEmpty {
                    // Check file extension safety
                    let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
                    guard ext == "mp4" || ext == "mov" else { continue }
                    
                    let fileURL = documentsURL.appendingPathComponent(fileName)
                    let fileData = Data(part.body)
                    
                    do {
                        try fileData.write(to: fileURL)
                        print("Saved file to: \(fileURL.path)")
                    } catch {
                        print("Failed to save uploaded file: \(error)")
                        return .internalServerError
                    }
                }
            }
            return .ok(.text("OK"))
        }
        
        // POST API to delete file
        server.POST["/delete"] = { request in
            let query = request.queryParams
            guard let name = query.first(where: { $0.0 == "name" })?.1 else {
                return .badRequest(nil)
            }
            
            let fileURL = documentsURL.appendingPathComponent(name)
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    return .ok(.text("Deleted"))
                }
                return .notFound
            } catch {
                print("Error deleting file via API: \(error)")
                return .internalServerError
            }
        }
        
        do {
            try server.start(serverPort)
            self.server = server
            self.serverIP = self.getWiFiAddress()
            self.isRunning = true
        } catch {
            print("Swifter server start failed: \(error)")
        }
    }
    
    // Stop server socket
    func stopServer() {
        server?.stop()
        server = nil
        serverIP = nil
        isRunning = false
    }
    
    // Helper to extract device IPv4 on the local network Wi-Fi interface (en0)
    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)
            
            // en0 is the default Wi-Fi interface identifier on iOS devices
            if name == "en0" {
                if addrFamily == UInt8(AF_INET) { // IPv4
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
    
    // Portal HTML String
    private func portalHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>iOS Video Player - Web Upload Portal</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: #121212;
                    color: #E0E0E0;
                    margin: 0;
                    padding: 20px;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                }
                .container {
                    max-width: 600px;
                    width: 100%;
                    background: #1E1E1E;
                    padding: 20px;
                    border-radius: 12px;
                    box-shadow: 0 4px 10px rgba(0,0,0,0.3);
                }
                h1 {
                    text-align: center;
                    color: #007AFF;
                    font-size: 24px;
                    margin-bottom: 20px;
                }
                .dropzone {
                    border: 2px dashed #007AFF;
                    border-radius: 8px;
                    padding: 30px;
                    text-align: center;
                    background: #252525;
                    cursor: pointer;
                    transition: background 0.3s;
                    margin-bottom: 20px;
                }
                .dropzone:hover, .dropzone.dragover {
                    background: #2C2C2C;
                }
                .file-list {
                    list-style: none;
                    padding: 0;
                    margin: 0;
                }
                .file-item {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    padding: 10px;
                    background: #252525;
                    border-radius: 6px;
                    margin-bottom: 8px;
                }
                .file-info {
                    display: flex;
                    flex-direction: column;
                }
                .file-name {
                    font-weight: 500;
                    word-break: break-all;
                }
                .file-size {
                    font-size: 12px;
                    color: #888;
                    margin-top: 2px;
                }
                .btn {
                    background: #007AFF;
                    color: white;
                    border: none;
                    padding: 6px 12px;
                    border-radius: 4px;
                    cursor: pointer;
                    text-decoration: none;
                    font-size: 14px;
                    transition: background 0.2s;
                }
                .btn:hover {
                    background: #0056B3;
                }
                .btn-delete {
                    background: #FF3B30;
                }
                .btn-delete:hover {
                    background: #C73E3A;
                }
                .progress-bar {
                    width: 100%;
                    height: 8px;
                    background-color: #333;
                    border-radius: 4px;
                    overflow: hidden;
                    display: none;
                    margin-bottom: 20px;
                }
                .progress-fill {
                    height: 100%;
                    background-color: #30D158;
                    width: 0%;
                    transition: width 0.1s;
                }
                #fileInput {
                    display: none;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>iOS Video Player Wi-Fi Portal</h1>
                
                <div class="dropzone" id="dropzone">
                    Drag & Drop video files (.mp4 or .mov) here or click to select
                </div>
                <input type="file" id="fileInput" accept=".mp4,.mov" multiple>
                
                <div class="progress-bar" id="progressBar">
                    <div class="progress-fill" id="progressFill"></div>
                </div>
                
                <h2>Available Videos</h2>
                <ul class="file-list" id="fileList">
                    <!-- Dynamically populated -->
                </ul>
            </div>

            <script>
                const dropzone = document.getElementById('dropzone');
                const fileInput = document.getElementById('fileInput');
                const progressBar = document.getElementById('progressBar');
                const progressFill = document.getElementById('progressFill');
                const fileList = document.getElementById('fileList');

                dropzone.addEventListener('click', () => fileInput.click());

                dropzone.addEventListener('dragover', (e) => {
                    e.preventDefault();
                    dropzone.classList.add('dragover');
                });

                dropzone.addEventListener('dragleave', () => {
                    dropzone.classList.remove('dragover');
                });

                dropzone.addEventListener('drop', (e) => {
                    e.preventDefault();
                    dropzone.classList.remove('dragover');
                    handleFiles(e.dataTransfer.files);
                });

                fileInput.addEventListener('change', () => {
                    handleFiles(fileInput.files);
                });

                function handleFiles(files) {
                    if (files.length === 0) return;
                    progressBar.style.display = 'block';
                    uploadFile(files, 0);
                }

                function uploadFile(files, index) {
                    if (index >= files.length) {
                        progressBar.style.display = 'none';
                        loadFiles();
                        return;
                    }
                    const file = files[index];
                    const formData = new FormData();
                    formData.append('file', file);

                    const xhr = new XMLHttpRequest();
                    xhr.open('POST', '/upload', true);

                    xhr.upload.onprogress = (e) => {
                        if (e.lengthComputable) {
                            const percentComplete = (e.loaded / e.total) * 100;
                            progressFill.style.width = percentComplete + '%';
                        }
                    };

                    xhr.onload = () => {
                        if (xhr.status === 200) {
                            uploadFile(files, index + 1);
                        } else {
                            alert('Failed to upload: ' + file.name);
                            progressBar.style.display = 'none';
                        }
                    };

                    xhr.send(formData);
                }

                function loadFiles() {
                    fetch('/list')
                        .then(res => res.json())
                        .then(data => {
                            fileList.innerHTML = '';
                            if (data.length === 0) {
                                fileList.innerHTML = '<p style="text-align: center; color: #888;">No videos uploaded yet.</p>';
                                return;
                            }
                            data.forEach(file => {
                                const li = document.createElement('li');
                                li.className = 'file-item';
                                li.innerHTML = `
                                    <div class="file-info">
                                        <span class="file-name">${file.name}</span>
                                        <span class="file-size">${file.size}</span>
                                    </div>
                                    <div style="display: flex; gap: 8px;">
                                        <a href="/files/${encodeURIComponent(file.name)}" class="btn" download>Download</a>
                                        <button onclick="deleteFile('${file.name}')" class="btn btn-delete">Delete</button>
                                    </div>
                                `;
                                fileList.appendChild(li);
                            });
                        });
                }

                function deleteFile(name) {
                    if (!confirm('Are you sure you want to delete ' + name + '?')) return;
                    fetch('/delete?name=' + encodeURIComponent(name), { method: 'POST' })
                        .then(res => {
                            if (res.ok) loadFiles();
                            else alert('Failed to delete file');
                        });
                }

                loadFiles();
            </script>
        </body>
        </html>
        """
    }
}
