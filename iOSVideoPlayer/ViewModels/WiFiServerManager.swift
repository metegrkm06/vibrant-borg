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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }

            let requestStr = String(data: data, encoding: .utf8) ?? ""
            let response = self.routeRequest(requestStr, rawData: data)
            self.sendResponse(response, on: connection)
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
            // Serve files from /files/
            if path.hasPrefix("/files/") {
                return serveFile(path: path)
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
        let name = String(path.dropFirst("/files/".count))
            .removingPercentEncoding ?? ""
        let fileURL = documentsURL.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return .plain(404, "Not Found")
        }
        return .file(200, data, name)
    }

    private func handleUpload(rawData: Data, headers: [String]) -> HTTPResponse {
        // Parse multipart boundary from Content-Type header
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
            // Remove trailing \r\n
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
            <style>
                body { font-family: -apple-system, sans-serif; background: #121212; color: #E0E0E0; margin: 0; padding: 20px; display: flex; flex-direction: column; align-items: center; }
                .container { max-width: 600px; width: 100%; background: #1E1E1E; padding: 20px; border-radius: 12px; }
                h1 { text-align: center; color: #007AFF; }
                .dropzone { border: 2px dashed #007AFF; border-radius: 8px; padding: 30px; text-align: center; background: #252525; cursor: pointer; margin-bottom: 20px; }
                .file-item { display: flex; justify-content: space-between; align-items: center; padding: 10px; background: #252525; border-radius: 6px; margin-bottom: 8px; }
                .btn { background: #007AFF; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer; text-decoration: none; font-size: 14px; }
                .btn-delete { background: #FF3B30; }
                .progress-bar { width: 100%; height: 8px; background: #333; border-radius: 4px; display: none; margin-bottom: 20px; }
                .progress-fill { height: 100%; background: #30D158; width: 0%; transition: width 0.1s; }
                #fileInput { display: none; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>📺 Video Player Wi-Fi Portal</h1>
                <div class="dropzone" id="dropzone">Drag & Drop .mp4 or .mov files here, or click to select</div>
                <input type="file" id="fileInput" accept=".mp4,.mov" multiple>
                <div class="progress-bar" id="progressBar"><div class="progress-fill" id="progressFill"></div></div>
                <h2>Videos</h2>
                <ul id="fileList" style="list-style:none;padding:0;"></ul>
            </div>
            <script>
                const dropzone = document.getElementById('dropzone');
                const fileInput = document.getElementById('fileInput');
                const progressBar = document.getElementById('progressBar');
                const progressFill = document.getElementById('progressFill');
                const fileList = document.getElementById('fileList');
                dropzone.addEventListener('click', () => fileInput.click());
                dropzone.addEventListener('dragover', e => { e.preventDefault(); dropzone.style.background='#2C2C2C'; });
                dropzone.addEventListener('dragleave', () => { dropzone.style.background='#252525'; });
                dropzone.addEventListener('drop', e => { e.preventDefault(); dropzone.style.background='#252525'; handleFiles(e.dataTransfer.files); });
                fileInput.addEventListener('change', () => handleFiles(fileInput.files));
                function handleFiles(files) { if (!files.length) return; progressBar.style.display='block'; uploadFile(files, 0); }
                function uploadFile(files, i) {
                    if (i >= files.length) { progressBar.style.display='none'; loadFiles(); return; }
                    const fd = new FormData(); fd.append('file', files[i]);
                    const xhr = new XMLHttpRequest(); xhr.open('POST', '/upload', true);
                    xhr.upload.onprogress = e => { if (e.lengthComputable) progressFill.style.width=(e.loaded/e.total*100)+'%'; };
                    xhr.onload = () => { if (xhr.status===200) uploadFile(files, i+1); else { alert('Upload failed'); progressBar.style.display='none'; } };
                    xhr.send(fd);
                }
                function loadFiles() {
                    fetch('/list').then(r=>r.json()).then(data => {
                        fileList.innerHTML = data.length ? '' : '<li style="color:#888;text-align:center">No videos yet.</li>';
                        data.forEach(f => {
                            const li = document.createElement('li'); li.className='file-item';
                            li.innerHTML=`<span>${f.name}<br><small style="color:#888">${f.size}</small></span><div><a href="/files/${encodeURIComponent(f.name)}" class="btn" download>⬇</a> <button onclick="deleteFile('${f.name}')" class="btn btn-delete">🗑</button></div>`;
                            fileList.appendChild(li);
                        });
                    });
                }
                function deleteFile(n) { if(!confirm('Delete '+n+'?')) return; fetch('/delete?name='+encodeURIComponent(n),{method:'POST'}).then(r=>{ if(r.ok) loadFiles(); }); }
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
    case file(Int, Data, String)

    var data: Data {
        switch self {
        case .plain(let code, let body):
            return buildResponse(code: code, contentType: "text/plain", body: body.data(using: .utf8)!)
        case .html(let code, let body):
            return buildResponse(code: code, contentType: "text/html; charset=utf-8", body: body.data(using: .utf8)!)
        case .json(let code, let body):
            return buildResponse(code: code, contentType: "application/json", body: body.data(using: .utf8)!)
        case .file(let code, let body, let name):
            return buildResponse(code: code, contentType: "application/octet-stream", body: body,
                                 extra: "Content-Disposition: attachment; filename=\"\(name)\"")
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
