import SwiftUI

struct WiFiSharingView: View {
    @ObservedObject var wifiManager: WiFiServerManager
    @StateObject private var vdsManager = VDSNetworkManager()
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedMode = 0 // 0: Local, 1: Online (VDS)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Mode", selection: $selectedMode) {
                    Text("Local Wi-Fi").tag(0)
                    Text("Online VDS").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                if selectedMode == 0 {
                    localWiFiView
                } else {
                    onlineVDSView
                }
            }
            .navigationTitle("Network Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        wifiManager.stopServer() // Auto stop to save battery
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Local Wi-Fi View
    private var localWiFiView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: wifiManager.isRunning ? "wifi" : "wifi.slash")
                .font(.system(size: 80))
                .foregroundColor(wifiManager.isRunning ? .green : .secondary)
                .padding()
                .background(
                    Circle()
                        .fill(wifiManager.isRunning ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 140, height: 140)
                )
            
            VStack(spacing: 8) {
                Text(wifiManager.isRunning ? "Server is Running" : "Local Wi-Fi Server")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Transfer videos from other devices on the same Wi-Fi network.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            if wifiManager.isRunning {
                VStack(spacing: 12) {
                    Text("Open this address in your browser:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let url = wifiManager.serverURL {
                        Text(url)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .textSelection(.enabled)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    } else {
                        Text("No Wi-Fi Connection")
                            .foregroundColor(.red)
                    }
                }
                .transition(.scale)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    if wifiManager.isRunning {
                        wifiManager.stopServer()
                    } else {
                        wifiManager.startServer()
                    }
                }
            }) {
                Text(wifiManager.isRunning ? "Stop Server" : "Start Server")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(wifiManager.isRunning ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }
    
    // MARK: - Online VDS View
    private var onlineVDSView: some View {
        VStack(spacing: 0) {
            // Configuration Form
            Form {
                Section(header: Text("VDS Configuration")) {
                    TextField("IP Address (e.g. 192.168.1.100 or domain)", text: $vdsManager.vdsIP)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Port (e.g. 3000)", text: $vdsManager.vdsPort)
                        .keyboardType(.numberPad)
                    SecureField("Secret Token", text: $vdsManager.secretToken)
                    
                    Button("Connect & Fetch Videos") {
                        vdsManager.fetchVideos()
                    }
                    .disabled(vdsManager.vdsIP.isEmpty || vdsManager.secretToken.isEmpty)
                }
                
                if let error = vdsManager.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red).font(.subheadline)
                    }
                }
                
                if vdsManager.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Connecting to VDS...")
                            Spacer()
                        }
                    }
                } else if !vdsManager.remoteVideos.isEmpty {
                    Section(header: Text("Remote Videos")) {
                        ForEach(vdsManager.remoteVideos) { video in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(video.filename)
                                        .font(.headline)
                                    Text("\(video.sizeBytes / 1024 / 1024) MB")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                
                                Button(action: {
                                    vdsManager.downloadVideo(video) { success in
                                        if success {
                                            // Notify user somehow, maybe fetch library
                                        }
                                    }
                                }) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                }
                                .disabled(vdsManager.isDownloading)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }
}
