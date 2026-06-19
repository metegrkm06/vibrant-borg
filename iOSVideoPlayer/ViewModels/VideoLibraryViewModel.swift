import Foundation
import UIKit
import AVFoundation

class VideoLibraryViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading: Bool = false
    @Published var searchText: String = ""
    @Published var sortBy: SortOption = .dateAdded
    @Published var showFavoritesOnly: Bool = false
    
    enum SortOption {
        case name
        case dateAdded
        case duration
    }
    
    private let fileManager = FileManager.default
    
    // Read and write bookmarked favorites in UserDefaults
    private var favoriteIDs: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: "FavoriteVideoIDs") ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "FavoriteVideoIDs")
        }
    }
    
    // Computes filtered and sorted list of videos
    var filteredVideos: [Video] {
        var result = videos
        
        // Search filter (ignores case)
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Favorites filter
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }
        
        // Sorting logic
        switch sortBy {
        case .name:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dateAdded:
            result.sort { $0.dateAdded > $1.dateAdded } // Newest first
        case .duration:
            result.sort { $0.duration > $1.duration } // Longest first
        }
        
        return result
    }
    
    init() {
        scanDocumentsDirectory()
    }
    
    // Scans Documents directory for MP4 and MOV files
    func scanDocumentsDirectory() {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let fileURLs = try self.fileManager.contentsOfDirectory(
                    at: documentsURL,
                    includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
                
                // Keep only .mp4 and .mov extensions
                let videoURLs = fileURLs.filter { url in
                    let ext = url.pathExtension.lowercased()
                    return ext == "mp4" || ext == "mov"
                }
                
                var scannedVideos: [Video] = []
                let favs = self.favoriteIDs
                
                for url in videoURLs {
                    let filename = url.lastPathComponent
                    let title = url.deletingPathExtension().lastPathComponent
                    
                    let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                    let dateAdded = resourceValues?.creationDate ?? Date()
                    let fileSize = Int64(resourceValues?.fileSize ?? 0)
                    
                    let asset = AVAsset(url: url)
                    let duration = asset.duration.seconds
                    let isFav = favs.contains(filename)
                    
                    let video = Video(
                        id: UUID(),
                        url: url,
                        title: title,
                        thumbnail: nil,
                        duration: duration.isNaN ? 0 : duration,
                        dateAdded: dateAdded,
                        fileSize: fileSize,
                        isFavorite: isFav
                    )
                    
                    scannedVideos.append(video)
                }
                
                DispatchQueue.main.async {
                    self.videos = scannedVideos
                    self.isLoading = false
                    // Start generating thumbnails for scanned videos
                    self.generateThumbnails()
                }
                
            } catch {
                print("Error scanning Documents directory: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
    
    // Generates 1:1 ratio thumbnails asynchronously using AVAssetImageGenerator
    func generateThumbnails() {
        for index in 0..<videos.count {
            let video = videos[index]
            guard video.thumbnail == nil else { continue }
            
            let asset = AVAsset(url: video.url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 300, height: 300) // Optimal size for square grid cells
            
            // Capture frame from the first second or half-duration of the video
            let time = CMTime(seconds: min(1.0, video.duration / 2), preferredTimescale: 600)
            
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] _, image, _, result, _ in
                guard let self = self, result == .succeeded, let image = image else { return }
                
                let uiImage = UIImage(cgImage: image)
                DispatchQueue.main.async {
                    if index < self.videos.count && self.videos[index].url == video.url {
                        self.videos[index].thumbnail = uiImage
                    }
                }
            }
        }
    }
    
    // Toggle video bookmark status
    func toggleFavorite(for video: Video) {
        if let index = videos.firstIndex(where: { $0.url == video.url }) {
            videos[index].isFavorite.toggle()
            
            let filename = video.url.lastPathComponent
            var favs = favoriteIDs
            if videos[index].isFavorite {
                favs.insert(filename)
            } else {
                favs.remove(filename)
            }
            favoriteIDs = favs
        }
    }
    
    // Delete video file from local sandboxed storage
    func deleteVideo(at url: URL) {
        do {
            try fileManager.removeItem(at: url)
            videos.removeAll { $0.url == url }
            
            let filename = url.lastPathComponent
            var favs = favoriteIDs
            favs.remove(filename)
            favoriteIDs = favs
        } catch {
            print("Error deleting video file: \(error)")
        }
    }
}
