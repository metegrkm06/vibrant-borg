import Foundation
import Network

// WiFi server implemented using Apple's native Network framework (no external deps)
// Uses NWListener for TCP server, serving a minimal HTTP portal on port 8080
class WiFiServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var serverIP: String?
    @Published var serverPort: UInt16 = 8080

    private var listener: NWListener?
    private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private let queue = DispatchQueue(label: "wifi.server.queue", qos: .userInitiated)

    var serverURL: String? {
        guard let ip = serverIP else { return nil }
        return "http://\(ip):\(serverPort)"
    }

    func startServer() {
        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: serverPort)!)
        } catch {
            print("Failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .global())
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.serverIP = self.getWiFiAddress()
                    self.isRunning = true
                case .failed(let err):
                    print("Listener failed: \(err)")
                    self.isRunning = false
                case .cancelled:
                    self.isRunning = false
                default:
                    break
                }
            }
        }

        listener?.start(queue: queue)
    }

    func stopServer() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.serverIP = nil
            self.isRunning = false
        }
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        let parser = HTTPRequestParser()
        readNextChunk(connection: connection, parser: parser)
    }

    private func readNextChunk(connection: NWConnection, parser: HTTPRequestParser) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Receive error: \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, !data.isEmpty else {
                if isComplete {
                    let headersData = parser.headersData()
                    let headersStr = String(data: headersData, encoding: .utf8) ?? ""
                    let response = self.routeRequest(headersStr, rawData: parser.buffer)
                    self.sendResponse(response, on: connection)
                } else {
                    connection.cancel()
                }
                return
            }
            
            let isFinished = parser.append(data)
            if isFinished || isComplete {
                let headersData = parser.headersData()
                let headersStr = String(data: headersData, encoding: .utf8) ?? ""
                let response = self.routeRequest(headersStr, rawData: parser.buffer)
                self.sendResponse(response, on: connection)
            } else {
                self.readNextChunk(connection: connection, parser: parser)
            }
        }
    }

    private func routeRequest(_ request: String, rawData: Data) -> HTTPResponse {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return .plain(404, "Not Found") }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return .plain(400, "Bad Request") }
        let method = parts[0]
        let path = parts[1].components(separatedBy: "?").first ?? parts[1]
        let query = parts[1].components(separatedBy: "?").dropFirst().first ?? ""

        switch (method, path) {
        case ("GET", "/"):
            return .html(200, portalHTML())
        case ("GET", "/list"):
            return listFiles()
        case ("POST", "/upload"):
            return handleUpload(rawData: rawData, headers: lines)
        case ("POST", "/delete"):
            return handleDelete(query: query)
        default:
            if path.hasPrefix("/files/") {
                return serveFile(path: path)
            }
            if path.hasPrefix("/thumbnails/") {
                return serveThumbnail(path: path)
            }
            return .plain(404, "Not Found")
        }
    }

    // MARK: - Route Handlers

    private func listFiles() -> HTTPResponse {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: documentsURL,
                includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            let videos = urls.filter { ["mp4", "mov"].contains($0.pathExtension.lowercased()) }
            var list: [[String: String]] = []
            for url in videos {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                list.append([
                    "name": url.lastPathComponent,
                    "size": ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                ])
            }
            if let json = try? JSONSerialization.data(withJSONObject: list),
               let str = String(data: json, encoding: .utf8) {
                return .json(200, str)
            }
        } catch { print("List error: \(error)") }
        return .plain(500, "Error")
    }

    private func serveFile(path: String) -> HTTPResponse {
        let name = String(path.dropFirst("/files/".count)).removingPercentEncoding ?? ""
        let fileURL = documentsURL.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return .plain(404, "Not Found")
        }
        let ext = fileURL.pathExtension.lowercased()
        let contentType = ext == "mp4" ? "video/mp4" : ext == "mov" ? "video/quicktime" : "application/octet-stream"
        return .file(200, data, name, contentType)
    }

    private func serveThumbnail(path: String) -> HTTPResponse {
        let name = String(path.dropFirst("/thumbnails/".count)).removingPercentEncoding ?? ""
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileURL = cacheURL.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return .plain(404, "Not Found")
        }
        return .file(200, data, name, "image/jpeg")
    }

    private func handleUpload(rawData: Data, headers: [String]) -> HTTPResponse {
        guard let contentTypeLine = headers.first(where: { $0.lowercased().hasPrefix("content-type:") }),
              let boundary = contentTypeLine.components(separatedBy: "boundary=").last else {
            return .plain(400, "No boundary")
        }

        let boundaryData = ("--" + boundary).data(using: .utf8)!
        let parts = rawData.components(separatedBy: boundaryData)

        for part in parts.dropFirst() {
            guard let headerEnd = part.range(of: "\r\n\r\n".data(using: .utf8)!) else { continue }
            let headerData = part[part.startIndex..<headerEnd.lowerBound]
            let headerStr = String(data: headerData, encoding: .utf8) ?? ""

            guard let fileNameRange = headerStr.range(of: "filename=\""),
                  let fileNameEnd = headerStr[fileNameRange.upperBound...].range(of: "\"") else { continue }

            let fileName = String(headerStr[fileNameRange.upperBound..<fileNameEnd.lowerBound])
            let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
            guard ext == "mp4" || ext == "mov" else { continue }

            let bodyStart = part.index(headerEnd.upperBound, offsetBy: 0)
            var body = part[bodyStart...]
            if body.suffix(2) == "\r\n".data(using: .utf8) {
                body = body.dropLast(2)
            }

            let fileURL = documentsURL.appendingPathComponent(fileName)
            try? Data(body).write(to: fileURL)
        }

        return .plain(200, "OK")
    }

    private func handleDelete(query: String) -> HTTPResponse {
        let params = query.components(separatedBy: "&")
        guard let nameParam = params.first(where: { $0.hasPrefix("name=") }),
              let name = nameParam.components(separatedBy: "=").last?.removingPercentEncoding else {
            return .plain(400, "Missing name")
        }
        let fileURL = documentsURL.appendingPathComponent(name)
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                // Also remove cached thumbnail if it exists
                let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                let thumbURL = cacheURL.appendingPathComponent(name + ".jpg")
                try? FileManager.default.removeItem(at: thumbURL)
                return .plain(200, "Deleted")
            }
            return .plain(404, "Not Found")
        } catch {
            return .plain(500, "Error")
        }
    }

    // MARK: - HTTP Response

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let data = response.data
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Wi-Fi IP Detection

    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let name = String(cString: interface.ifa_name)
            if name == "en0", interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                address = String(cString: hostname)
            }
        }
        freeifaddrs(ifaddr)
        return address
    }

    // MARK: - Portal HTML

    private func portalHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>iOS Video Player - Wi-Fi Portal</title>
            <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
            <style>
                :root {
                    --bg-color: #0b0f19;
                    --panel-bg: rgba(20, 26, 42, 0.75);
                    --border-color: rgba(255, 255, 255, 0.08);
                    --accent-color: #3b82f6;
                    --accent-hover: #2563eb;
                    --text-primary: #f3f4f6;
                    --text-secondary: #9ca3af;
                    --card-bg: rgba(30, 41, 59, 0.45);
                    --danger-color: #ef4444;
                }
                body {
                    font-family: 'Inter', -apple-system, sans-serif;
                    background: var(--bg-color);
                    color: var(--text-primary);
                    margin: 0;
                    padding: 40px 20px;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    min-height: 100vh;
                }
                .container {
                    max-width: 900px;
                    width: 100%;
                    background: var(--panel-bg);
                    backdrop-filter: blur(16px);
                    -webkit-backdrop-filter: blur(16px);
                    border: 1px solid var(--border-color);
                    padding: 32px;
                    border-radius: 24px;
                    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
                }
                h1 {
                    text-align: center;
                    color: var(--text-primary);
                    font-weight: 700;
                    font-size: 28px;
                    margin-top: 0;
                    margin-bottom: 8px;
                }
                .status-badge {
                    font-size: 13px;
                    background: rgba(16, 185, 129, 0.12);
                    color: #10b981;
                    padding: 6px 16px;
                    border-radius: 9999px;
                    display: inline-block;
                    margin-bottom: 24px;
                    font-weight: 600;
                    letter-spacing: 0.5px;
                }
                .dropzone {
                    border: 2px dashed var(--accent-color);
                    border-radius: 16px;
                    padding: 40px 20px;
                    text-align: center;
                    background: rgba(59, 130, 246, 0.03);
                    cursor: pointer;
                    transition: all 0.3s ease;
                    margin-bottom: 24px;
                }
                .dropzone:hover {
                    background: rgba(59, 130, 246, 0.08);
                    border-color: #60a5fa;
                    transform: translateY(-2px);
                }
                .dropzone-icon {
                    font-size: 40px;
                    margin-bottom: 12px;
                }
                .dropzone-text {
                    font-weight: 600;
                    font-size: 16px;
                    color: var(--text-primary);
                }
                .dropzone-subtext {
                    font-size: 13px;
                    color: var(--text-secondary);
                    margin-top: 6px;
                }
                .progress-bar {
                    width: 100%;
                    height: 8px;
                    background: rgba(255, 255, 255, 0.08);
                    border-radius: 999px;
                    display: none;
                    margin-bottom: 24px;
                    overflow: hidden;
                }
                .progress-fill {
                    height: 100%;
                    background: var(--accent-color);
                    width: 0%;
                    transition: width 0.1s;
                    box-shadow: 0 0 10px var(--accent-color);
                }
                h2 {
                    font-size: 20px;
                    font-weight: 600;
                    margin-top: 12px;
                    margin-bottom: 20px;
                    border-bottom: 1px solid var(--border-color);
                    padding-bottom: 10px;
                }
                .video-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
                    gap: 20px;
                    padding: 0;
                    list-style: none;
                    margin: 0;
                }
                .video-card {
                    background: var(--card-bg);
                    border: 1px solid var(--border-color);
                    border-radius: 16px;
                    overflow: hidden;
                    transition: all 0.3s ease;
                    display: flex;
                    flex-direction: column;
                    position: relative;
                }
                .video-card:hover {
                    transform: translateY(-4px);
                    box-shadow: 0 8px 20px rgba(0,0,0,0.4);
                    border-color: rgba(255, 255, 255, 0.15);
                }
                .thumbnail-container {
                    width: 100%;
                    padding-top: 100%;
                    position: relative;
                    background: #000;
                    cursor: pointer;
                    overflow: hidden;
                }
                .thumbnail-img {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    object-fit: cover;
                    transition: transform 0.5s ease;
                }
                .video-card:hover .thumbnail-img {
                    transform: scale(1.08);
                }
                .play-overlay {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    background: rgba(0,0,0,0.4);
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    opacity: 0;
                    transition: opacity 0.3s ease;
                }
                .video-card:hover .play-overlay {
                    opacity: 1;
                }
                .play-icon {
                    width: 48px;
                    height: 48px;
                    background: var(--accent-color);
                    border-radius: 50%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    color: white;
                    font-size: 20px;
                    box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4);
                    transform: scale(0.8);
                    transition: transform 0.3s ease;
                    padding-left: 3px;
                }
                .video-card:hover .play-icon {
                    transform: scale(1);
                }
                .video-info {
                    padding: 12px;
                    display: flex;
                    flex-direction: column;
                    flex-grow: 1;
                    justify-content: space-between;
                }
                .video-title {
                    font-size: 14px;
                    font-weight: 600;
                    margin: 0 0 6px 0;
                    color: var(--text-primary);
                    overflow: hidden;
                    text-overflow: ellipsis;
                    white-space: nowrap;
                }
                .video-meta {
                    font-size: 12px;
                    color: var(--text-secondary);
                    margin-bottom: 12px;
                }
                .action-buttons {
                    display: flex;
                    gap: 8px;
                }
                .btn {
                    flex: 1;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    gap: 6px;
                    background: rgba(255,255,255,0.06);
                    color: var(--text-primary);
                    border: 1px solid var(--border-color);
                    padding: 8px 0;
                    border-radius: 8px;
                    cursor: pointer;
                    text-decoration: none;
                    font-size: 13px;
                    font-weight: 500;
                    transition: all 0.2s ease;
                }
                .btn:hover {
                    background: rgba(255,255,255,0.12);
                }
                .btn-download {
                    background: var(--accent-color);
                    border: none;
                }
                .btn-download:hover {
                    background: var(--accent-hover);
                }
                .btn-delete {
                    color: var(--danger-color);
                }
                .btn-delete:hover {
                    background: rgba(239, 68, 68, 0.1);
                    border-color: rgba(239, 68, 68, 0.2);
                }
                #fileInput { display: none; }
                
                .modal {
                    position: fixed;
                    top: 0; left: 0; width: 100%; height: 100%;
                    background: rgba(0,0,0,0.85);
                    backdrop-filter: blur(8px);
                    -webkit-backdrop-filter: blur(8px);
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    opacity: 0;
                    pointer-events: none;
                    transition: opacity 0.3s ease;
                    z-index: 1000;
                }
                .modal.active {
                    opacity: 1;
                    pointer-events: auto;
                }
                .modal-content {
                    width: 90%;
                    max-width: 800px;
                    background: #101424;
                    border-radius: 20px;
                    overflow: hidden;
                    border: 1px solid var(--border-color);
                    box-shadow: 0 20px 50px rgba(0,0,0,0.5);
                    transform: scale(0.95);
                    transition: transform 0.3s ease;
                }
                .modal.active .modal-content {
                    transform: scale(1);
                }
                .modal-header {
                    padding: 16px 20px;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    border-bottom: 1px solid var(--border-color);
                }
                .modal-title {
                    font-weight: 600;
                    margin: 0;
                    font-size: 16px;
                }
                .modal-close {
                    background: none;
                    border: none;
                    color: var(--text-secondary);
                    font-size: 24px;
                    cursor: pointer;
                }
                .modal-close:hover {
                    color: var(--text-primary);
                }
                video {
                    width: 100%;
                    display: block;
                    background: #000;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>📺 Video Player Wi-Fi Portal</h1>
                <div style="text-align: center;">
                    <span class="status-badge">● Connected & Active</span>
                </div>
                
                <div class="dropzone" id="dropzone">
                    <div class="dropzone-icon">☁️</div>
                    <div class="dropzone-text">Drag & drop video files here</div>
                    <div class="dropzone-subtext">Supports MP4 and MOV formats • Click to browse</div>
                </div>
                
                <input type="file" id="fileInput" accept=".mp4,.mov" multiple>
                <div class="progress-bar" id="progressBar"><div class="progress-fill" id="progressFill"></div></div>
                
                <h2>Videos</h2>
                <ul class="video-grid" id="fileList"></ul>
            </div>

            <div class="modal" id="videoModal">
                <div class="modal-content">
                    <div class="modal-header">
                        <h3 class="modal-title" id="modalTitle">Video Player</h3>
                        <button class="modal-close" onclick="closePlayer()">&times;</button>
                    </div>
                    <video id="videoPlayer" controls></video>
                </div>
            </div>

            <script>
                const dropzone = document.getElementById('dropzone');
                const fileInput = document.getElementById('fileInput');
                const progressBar = document.getElementById('progressBar');
                const progressFill = document.getElementById('progressFill');
                const fileList = document.getElementById('fileList');
                const videoModal = document.getElementById('videoModal');
                const videoPlayer = document.getElementById('videoPlayer');
                const modalTitle = document.getElementById('modalTitle');

                dropzone.addEventListener('click', () => fileInput.click());
                dropzone.addEventListener('dragover', e => { e.preventDefault(); });
                dropzone.addEventListener('drop', e => { e.preventDefault(); handleFiles(e.dataTransfer.files); });
                fileInput.addEventListener('change', () => handleFiles(fileInput.files));

                function handleFiles(files) {
                    if (!files.length) return;
                    progressBar.style.display = 'block';
                    uploadFile(files, 0);
                }

                function uploadFile(files, i) {
                    if (i >= files.length) {
                        progressBar.style.display = 'none';
                        progressFill.style.width = '0%';
                        loadFiles();
                        return;
                    }
                    const fd = new FormData();
                    fd.append('file', files[i]);
                    const xhr = new XMLHttpRequest();
                    xhr.open('POST', '/upload', true);
                    xhr.upload.onprogress = e => {
                        if (e.lengthComputable) {
                            progressFill.style.width = (e.loaded / e.total * 100) + '%';
                        }
                    };
                    xhr.onload = () => {
                        if (xhr.status === 200) {
                            uploadFile(files, i + 1);
                        } else {
                            alert('Upload failed: ' + xhr.responseText);
                            progressBar.style.display = 'none';
                        }
                    };
                    xhr.send(fd);
                }

                function loadFiles() {
                    fetch('/list')
                        .then(r => r.json())
                        .then(data => {
                            if (!data.length) {
                                fileList.innerHTML = '<li style="grid-column: 1/-1; color: var(--text-secondary); text-align: center; padding: 40px 0;">No videos yet. Add some to get started!</li>';
                                return;
                            }
                            fileList.innerHTML = '';
                            data.forEach(f => {
                                const li = document.createElement('li');
                                li.className = 'video-card';
                                li.innerHTML = `
                                    <div class="thumbnail-container" onclick="playVideo('${f.name}')">
                                        <img src="/thumbnails/${encodeURIComponent(f.name)}.jpg" class="thumbnail-img" onerror="this.src='data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%22100%22 height=%22100%22 viewBox=%220 0 100 100%22><rect width=%22100%25%22 height=%22100%25%22 fill=%22%231e293b%22/><text x=%2250%25%22 y=%2255%25%22 dominant-baseline=%22middle%22 text-anchor=%22middle%22 fill=%22%239ca3af%22 font-size=%2212%22>No Thumb</text></svg>'">
                                        <div class="play-overlay">
                                            <div class="play-icon">▶</div>
                                        </div>
                                    </div>
                                    <div class="video-info">
                                        <div>
                                            <h4 class="video-title" title="${f.name}">${f.name}</h4>
                                            <div class="video-meta">${f.size}</div>
                                        </div>
                                        <div class="action-buttons">
                                            <a href="/files/${encodeURIComponent(f.name)}" class="btn btn-download" download>⬇ Download</a>
                                            <button onclick="deleteFile('${f.name}')" class="btn btn-delete">🗑 Delete</button>
                                        </div>
                                    </div>
                                `;
                                fileList.appendChild(li);
                            });
                        });
                }

                function playVideo(name) {
                    modalTitle.textContent = name;
                    videoPlayer.src = '/files/' + encodeURIComponent(name);
                    videoModal.classList.add('active');
                    videoPlayer.play();
                }

                function closePlayer() {
                    videoPlayer.pause();
                    videoPlayer.src = '';
                    videoModal.classList.remove('active');
                }

                function deleteFile(n) {
                    if (!confirm('Are you sure you want to delete ' + n + '?')) return;
                    fetch('/delete?name=' + encodeURIComponent(n), { method: 'POST' })
                        .then(r => {
                            if (r.ok) loadFiles();
                        });
                }

                videoModal.addEventListener('click', e => {
                    if (e.target === videoModal) closePlayer();
                });

                loadFiles();
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - HTTPResponse helper

enum HTTPResponse {
    case plain(Int, String)
    case html(Int, String)
    case json(Int, String)
    case file(Int, Data, String, String) // code, data, name, contentType

    var data: Data {
        switch self {
        case .plain(let code, let body):
            return buildResponse(code: code, contentType: "text/plain", body: body.data(using: .utf8)!)
        case .html(let code, let body):
            return buildResponse(code: code, contentType: "text/html; charset=utf-8", body: body.data(using: .utf8)!)
        case .json(let code, let body):
            return buildResponse(code: code, contentType: "application/json", body: body.data(using: .utf8)!)
        case .file(let code, let body, let name, let contentType):
            return buildResponse(code: code, contentType: contentType, body: body,
                                 extra: "Content-Disposition: inline; filename=\"\(name)\"")
        }
    }

    private func buildResponse(code: Int, contentType: String, body: Data, extra: String = "") -> Data {
        let statusText = code == 200 ? "OK" : code == 404 ? "Not Found" : code == 400 ? "Bad Request" : "Error"
        var headers = "HTTP/1.1 \(code) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if !extra.isEmpty { headers += extra + "\r\n" }
        headers += "\r\n"
        var result = headers.data(using: .utf8)!
        result.append(body)
        return result
    }
}

// MARK: - HTTPRequestParser

class HTTPRequestParser {
    var buffer = Data()
    var headersLength: Int? = nil
    var contentLength: Int? = nil

    func append(_ data: Data) -> Bool {
        buffer.append(data)

        if headersLength == nil {
            if let range = buffer.range(of: "\r\n\r\n".data(using: .utf8)!) {
                headersLength = range.upperBound
                let headerData = buffer[buffer.startIndex..<range.lowerBound]
                if let headerStr = String(data: headerData, encoding: .utf8) {
                    let lines = headerStr.components(separatedBy: "\r\n")
                    for line in lines {
                        if line.lowercased().hasPrefix("content-length:") {
                            if let valStr = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines),
                               let val = Int(valStr) {
                                contentLength = val
                                break
                            }
                        }
                    }
                }
                if contentLength == nil {
                    contentLength = 0
                }
            }
        }

        if let headersLen = headersLength, let contentLen = contentLength {
            return buffer.count >= headersLen + contentLen
        }

        return false
    }

    func headersData() -> Data {
        if let len = headersLength {
            return buffer[buffer.startIndex..<len]
        }
        return buffer
    }
}

// MARK: - Data helper for multipart splitting

private extension Data {
    func components(separatedBy separator: Data) -> [Data] {
        var result: [Data] = []
        var start = startIndex
        while let range = self.range(of: separator, in: start..<endIndex) {
            result.append(self[start..<range.lowerBound])
            start = range.upperBound
        }
        result.append(self[start..<endIndex])
        return result
    }
}
