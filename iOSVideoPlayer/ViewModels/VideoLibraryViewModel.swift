import Foundation
import UIKit
import AVFoundation

class VideoLibraryViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading: Bool = false
    @Published var searchText: String = ""
    @Published var sortBy: SortOption = .dateAdded
    @Published var showFavoritesOnly: Bool = false
    @Published var playlists: [Playlist] = []
    @Published var selectedPlaylist: Playlist? = nil
    
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
    
    // Metadata dictionary mapping filename to VideoMetadata
    private var videoMetadata: [String: VideoMetadata] {
        get {
            if let data = UserDefaults.standard.data(forKey: "VideoMetadataDict"),
               let dict = try? JSONDecoder().decode([String: VideoMetadata].self, from: data) {
                return dict
            }
            return [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "VideoMetadataDict")
            }
        }
    }
    
    // Playlists persistence
    private var savedPlaylists: [Playlist] {
        get {
            if let data = UserDefaults.standard.data(forKey: "SavedPlaylists"),
               let array = try? JSONDecoder().decode([Playlist].self, from: data) {
                return array
            }
            return []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "SavedPlaylists")
            }
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
        
        // Playlist filter
        if let playlist = selectedPlaylist {
            result = result.filter { playlist.videoFilenames.contains($0.url.lastPathComponent) }
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
        self.playlists = savedPlaylists
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
                let metadataDict = self.videoMetadata
                let cacheURL = self.fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                
                for url in videoURLs {
                    let filename = url.lastPathComponent
                    let title = url.deletingPathExtension().lastPathComponent
                    
                    let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                    let dateAdded = resourceValues?.creationDate ?? Date()
                    let fileSize = Int64(resourceValues?.fileSize ?? 0)
                    
                    let asset = AVAsset(url: url)
                    let duration = asset.duration.seconds
                    let isFav = favs.contains(filename)
                    let meta = metadataDict[filename] ?? VideoMetadata()
                    
                    // Try to load cached thumbnail from Caches directory
                    let thumbURL = cacheURL.appendingPathComponent(filename + ".jpg")
                    let cachedImage = UIImage(contentsOfFile: thumbURL.path)
                    
                    let video = Video(
                        id: UUID(),
                        url: url,
                        title: title,
                        customTitle: meta.customTitle,
                        thumbnail: cachedImage,
                        duration: duration.isNaN ? 0 : duration,
                        dateAdded: dateAdded,
                        fileSize: fileSize,
                        isFavorite: isFav,
                        viewCount: meta.viewCount,
                        bookmarks: meta.bookmarks
                    )
                    
                    scannedVideos.append(video)
                }
                
                DispatchQueue.main.async {
                    self.videos = scannedVideos
                    self.isLoading = false
                    // Start generating thumbnails for scanned videos that lack them
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
        let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        
        for index in 0..<videos.count {
            let video = videos[index]
            guard video.thumbnail == nil else { continue }
            
            let asset = AVAsset(url: video.url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 300, height: 300) // Optimal size for square grid cells
            
            // Capture frame from the first second or half-duration of the video
            let time = CMTime(seconds: min(1.0, video.duration / 2), preferredTimescale: 600)
            
            let filename = video.url.lastPathComponent
            let thumbURL = cacheURL.appendingPathComponent(filename + ".jpg")
            
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] _, image, _, result, _ in
                guard let self = self, result == .succeeded, let image = image else { return }
                
                let uiImage = UIImage(cgImage: image)
                
                // Write image data to caches directory
                if let jpegData = uiImage.jpegData(compressionQuality: 0.85) {
                    try? jpegData.write(to: thumbURL)
                }
                
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
            
            // Delete cached thumbnail if it exists
            let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let thumbURL = cacheURL.appendingPathComponent(filename + ".jpg")
            try? fileManager.removeItem(at: thumbURL)
        } catch {
            print("Error deleting video file: \(error)")
        }
    }
    
    // MARK: - Metadata & Playlist Actions
    
    func renameVideo(_ video: Video, to newName: String) {
        let filename = video.url.lastPathComponent
        var dict = videoMetadata
        var meta = dict[filename] ?? VideoMetadata()
        meta.customTitle = newName.isEmpty ? nil : newName
        dict[filename] = meta
        videoMetadata = dict
        
        if let index = videos.firstIndex(where: { $0.id == video.id }) {
            videos[index].customTitle = meta.customTitle
        }
    }
    
    func incrementViewCount(for video: Video) {
        let filename = video.url.lastPathComponent
        var dict = videoMetadata
        var meta = dict[filename] ?? VideoMetadata()
        meta.viewCount += 1
        dict[filename] = meta
        videoMetadata = dict
        
        if let index = videos.firstIndex(where: { $0.id == video.id }) {
            videos[index].viewCount = meta.viewCount
        }
    }
    
    func addBookmark(to video: Video, at time: Double) {
        let filename = video.url.lastPathComponent
        var dict = videoMetadata
        var meta = dict[filename] ?? VideoMetadata()
        if !meta.bookmarks.contains(time) {
            meta.bookmarks.append(time)
            meta.bookmarks.sort()
            dict[filename] = meta
            videoMetadata = dict
            
            if let index = videos.firstIndex(where: { $0.id == video.id }) {
                videos[index].bookmarks = meta.bookmarks
            }
        }
    }

    func createPlaylist(name: String) {
        let newPlaylist = Playlist(name: name)
        playlists.append(newPlaylist)
        savedPlaylists = playlists
    }
    
    func addVideo(_ video: Video, to playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            let filename = video.url.lastPathComponent
            if !playlists[index].videoFilenames.contains(filename) {
                playlists[index].videoFilenames.append(filename)
                savedPlaylists = playlists
            }
        }
    }
    
    func removeVideo(_ video: Video, from playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            let filename = video.url.lastPathComponent
            playlists[index].videoFilenames.removeAll { $0 == filename }
            savedPlaylists = playlists
            
            if selectedPlaylist?.id == playlist.id {
                selectedPlaylist = playlists[index]
            }
        }
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        savedPlaylists = playlists
        if selectedPlaylist?.id == playlist.id {
            selectedPlaylist = nil
        }
    }
}
