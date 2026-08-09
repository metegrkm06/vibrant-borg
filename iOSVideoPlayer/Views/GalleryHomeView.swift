import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Photos

struct GalleryHomeView: View {
    @ObservedObject var viewModel: VideoLibraryViewModel
    @Binding var isUnlocked: Bool
    
    @StateObject private var wifiManager = WiFiServerManager()
    @State private var showWiFiModal = false
    @State private var showPhotoPicker = false
    @State private var showDeleteConfirmation = false
    @State private var importedAssetIdentifiers: [String] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Category Cards
                    NavigationLink(destination: VideoGridView(viewModel: viewModel)) {
                        CategoryCard(
                            title: "Videos",
                            count: viewModel.videos.count,
                            icon: "play.rectangle.fill",
                            gradient: [Color.blue, Color.purple],
                            thumbnail: viewModel.videos.first?.thumbnail
                        )
                    }
                    
                    NavigationLink(destination: ImageGalleryView(
                        images: viewModel.images,
                        onDelete: { item in
                            withAnimation { viewModel.deleteMediaItem(item) }
                        },
                        onRefresh: { viewModel.scanDocumentsDirectory() }
                    )) {
                        CategoryCard(
                            title: "Images",
                            count: viewModel.images.count,
                            icon: "photo.fill",
                            gradient: [Color.green, Color.teal],
                            thumbnail: viewModel.images.first?.thumbnail
                        )
                    }
                    
                    NavigationLink(destination: GifGalleryView(
                        gifs: viewModel.gifs,
                        onDelete: { item in
                            withAnimation { viewModel.deleteMediaItem(item) }
                        },
                        onRefresh: { viewModel.scanDocumentsDirectory() }
                    )) {
                        CategoryCard(
                            title: "GIFs",
                            count: viewModel.gifs.count,
                            icon: "photo.stack.fill",
                            gradient: [Color.orange, Color.pink],
                            thumbnail: viewModel.gifs.first?.thumbnail
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        withAnimation(.spring()) {
                            isUnlocked = false
                        }
                    }) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.red)
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Import from Photo Library
                    Button(action: { showPhotoPicker = true }) {
                        Image(systemName: "photo.badge.plus")
                    }
                    
                    // Wi-Fi Transfer
                    Button(action: { showWiFiModal = true }) {
                        Image(systemName: "wifi")
                    }
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(isPresented: $showPhotoPicker) { results in
                    let identifiers = results.compactMap { $0.assetIdentifier }
                    viewModel.importFromPhotoLibrary(results: results) { success in
                        if success && !identifiers.isEmpty {
                            self.importedAssetIdentifiers = identifiers
                            self.showDeleteConfirmation = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showWiFiModal, onDismiss: {
                viewModel.scanDocumentsDirectory()
            }) {
                WiFiSharingView(wifiManager: wifiManager)
            }
            .alert("Delete Imported Files?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteAssetsFromPhotoLibrary(identifiers: importedAssetIdentifiers)
                    importedAssetIdentifiers = []
                }
                Button("Keep", role: .cancel) {
                    importedAssetIdentifiers = []
                }
            } message: {
                Text("Do you want to delete the imported media from your system Photo Library?")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func deleteAssetsFromPhotoLibrary(identifiers: [String]) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count > 0 else { return }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets)
        }) { success, error in
            if let error = error {
                print("Error requesting photo deletion: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Category Card

struct CategoryCard: View {
    let title: String
    let count: Int
    let icon: String
    let gradient: [Color]
    let thumbnail: UIImage?
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background
            if let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 180)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                LinearGradient(
                    gradient: Gradient(colors: gradient),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 180)
            }
            
            // Content
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: icon)
                        .font(.title)
                        .foregroundColor(.white)
                    
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("\(count) items")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding()
        }
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

// MARK: - PhotoPicker representable for iOS 15 compatibility

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onSelection: ([PHPickerResult]) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 50
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        
        init(parent: PhotoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            parent.onSelection(results)
        }
    }
}
