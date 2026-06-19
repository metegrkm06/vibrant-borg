import SwiftUI

struct WiFiSharingView: View {
    @ObservedObject var wifiManager: WiFiServerManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
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
                                .textSelection(.enabled) // Enables URL copying
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
            .navigationTitle("Wi-Fi File Sharing")
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
}
