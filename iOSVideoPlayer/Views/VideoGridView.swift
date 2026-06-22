import SwiftUI

struct VideoGridView: View {
    @StateObject private var viewModel = VideoLibraryViewModel()
    @StateObject private var wifiManager = WiFiServerManager()
    
    @State private var showWiFiModal = false
    @State private var selectedVideo: Video?
    
    // Adaptable grid column layouts for iPhone/iPad responsive UI
    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
    ]
    
    private var searchAndFilterHeader: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search videos...", text: $viewModel.searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.primary)
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Favorites Toggle Button
            Button(action: {
                withAnimation {
                    viewModel.showFavoritesOnly.toggle()
                }
            }) {
                Image(systemName: viewModel.showFavoritesOnly ? "heart.fill" : "heart")
                    .foregroundColor(viewModel.showFavoritesOnly ? .red : .primary)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
            
            // Sorting Selector Button
            Menu {
                Button(action: { viewModel.sortBy = .name }) {
                    HStack {
                        Text("Sort by Name")
                        if viewModel.sortBy == .name { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { viewModel.sortBy = .dateAdded }) {
                    HStack {
                        Text("Sort by Date Added")
                        if viewModel.sortBy == .dateAdded { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { viewModel.sortBy = .duration }) {
                    HStack {
                        Text("Sort by Duration")
                        if viewModel.sortBy == .duration { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var mainContentArea: some View {
        if viewModel.isLoading {
            Spacer()
            ProgressView("Loading library...")
            Spacer()
        } else if viewModel.filteredVideos.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "video.slash")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text(viewModel.searchText.isEmpty ? "No videos found" : "No match for '\(viewModel.searchText)'")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Add videos by transferring them through the Wi-Fi sharing panel or using Files app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.filteredVideos) { video in
                        VideoCardView(video: video, onFavoriteToggle: {
                            viewModel.toggleFavorite(for: video)
                        })
                        .contextMenu {
                            Button(role: .destructive, action: {
                                viewModel.deleteVideo(at: video.url)
                            }) {
                                Label("Delete Video", systemImage: "trash")
                            }
                        }
                        .onTapGesture {
                            selectedVideo = video
                        }
                    }
                }
                .padding()
            }
            .refreshable {
                viewModel.scanDocumentsDirectory()
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchAndFilterHeader
                mainContentArea
            }
            .navigationTitle("Offline Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        if !viewModel.filteredVideos.isEmpty {
                            selectedVideo = viewModel.filteredVideos.randomElement()
                        }
                    }) {
                        Label("Random Video", systemImage: "shuffle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showWiFiModal = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "wifi")
                            Text("Wi-Fi Transfer")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                }
            }
            .sheet(item: $selectedVideo) { video in
                if let index = viewModel.filteredVideos.firstIndex(where: { $0.id == video.id }) {
                    VideoDetailPlayerView(videos: viewModel.filteredVideos, startIndex: index)
                } else {
                    VideoDetailPlayerView(videos: [video], startIndex: 0)
                }
            }
            .sheet(isPresented: $showWiFiModal, onDismiss: {
                // Re-scan when modal closes, as files might have changed
                viewModel.scanDocumentsDirectory()
            }) {
                WiFiSharingView(wifiManager: wifiManager)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // iPhone/iPad compatible
    }
}
