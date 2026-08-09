import Foundation
import UIKit
import AVFoundation
import PhotosUI
import ImageIO

class VideoLibraryViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var images: [MediaItem] = []
    @Published var gifs: [MediaItem] = []
    @Published var isLoading: Bool = false
    @Published var searchText: String = ""
    @Published var sortBy: SortOption = .dateAdded
    @Published var showFavoritesOnly: Bool = false
    @Published var playlists: [Playlist] = []
    @Published var selectedPlaylist: Playlist? = nil
    
    @Published var isDecoyMode: Bool = false {
        didSet {
            scanDocumentsDirectory()
        }
    }
    
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
    
    func scanDocumentsDirectory() {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let targetURL: URL
        if isDecoyMode {
            targetURL = documentsURL.appendingPathComponent("decoy")
            if !fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
            }
        } else {
            targetURL = documentsURL
        }
        
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let fileURLs = try self.fileManager.contentsOfDirectory(
                    at: targetURL,
                    includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
                
                let videoExtensions = Set(["mp4", "mov", "m4v"])
                let imageExtensions = Set(["jpg", "jpeg", "png", "heic", "webp"])
                let gifExtensions = Set(["gif"])
                
                // Keep only video extensions
                let videoURLs = fileURLs.filter { videoExtensions.contains($0.pathExtension.lowercased()) }
                let imageURLs = fileURLs.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
                let gifURLs = fileURLs.filter { gifExtensions.contains($0.pathExtension.lowercased()) }
                
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
                
                // Scan images
                var scannedImages: [MediaItem] = []
                for url in imageURLs {
                    let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                    let dateAdded = resourceValues?.creationDate ?? Date()
                    let fileSize = Int64(resourceValues?.fileSize ?? 0)
                    
                    // Generate thumbnail
                    let thumbURL = cacheURL.appendingPathComponent(url.lastPathComponent + ".thumb.jpg")
                    var thumb = UIImage(contentsOfFile: thumbURL.path)
                    if thumb == nil, let fullImage = UIImage(contentsOfFile: url.path) {
                        let size = CGSize(width: 200, height: 200)
                        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
                        fullImage.draw(in: CGRect(origin: .zero, size: size))
                        thumb = UIGraphicsGetImageFromCurrentImageContext()
                        UIGraphicsEndImageContext()
                        if let jpegData = thumb?.jpegData(compressionQuality: 0.7) {
                            try? jpegData.write(to: thumbURL)
                        }
                    }
                    
                    let item = MediaItem(
                        id: UUID(),
                        url: url,
                        filename: url.lastPathComponent,
                        thumbnail: thumb,
                        dateAdded: dateAdded,
                        fileSize: fileSize,
                        mediaType: .image
                    )
                    scannedImages.append(item)
                }
                
                // Scan GIFs
                var scannedGifs: [MediaItem] = []
                for url in gifURLs {
                    let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                    let dateAdded = resourceValues?.creationDate ?? Date()
                    let fileSize = Int64(resourceValues?.fileSize ?? 0)
                    
                    // Generate first-frame thumbnail for GIF
                    let thumbURL = cacheURL.appendingPathComponent(url.lastPathComponent + ".thumb.jpg")
                    var thumb = UIImage(contentsOfFile: thumbURL.path)
                    if thumb == nil, let data = try? Data(contentsOf: url),
                       let source = CGImageSourceCreateWithData(data as CFData, nil),
                       let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                        thumb = UIImage(cgImage: cgImage)
                        let size = CGSize(width: 200, height: 200)
                        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
                        thumb?.draw(in: CGRect(origin: .zero, size: size))
                        let resized = UIGraphicsGetImageFromCurrentImageContext()
                        UIGraphicsEndImageContext()
                        thumb = resized
                        if let jpegData = thumb?.jpegData(compressionQuality: 0.7) {
                            try? jpegData.write(to: thumbURL)
                        }
                    }
                    
                    let item = MediaItem(
                        id: UUID(),
                        url: url,
                        filename: url.lastPathComponent,
                        thumbnail: thumb,
                        dateAdded: dateAdded,
                        fileSize: fileSize,
                        mediaType: .gif
                    )
                    scannedGifs.append(item)
                }
                
                DispatchQueue.main.async {
                    self.videos = scannedVideos
                    self.images = scannedImages.sorted { $0.dateAdded > $1.dateAdded }
                    self.gifs = scannedGifs.sorted { $0.dateAdded > $1.dateAdded }
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
    
    // MARK: - Media Item Actions
    
    func deleteMediaItem(_ item: MediaItem) {
        do {
            try fileManager.removeItem(at: item.url)
            if item.mediaType == .image {
                images.removeAll { $0.url == item.url }
            } else {
                gifs.removeAll { $0.url == item.url }
            }
            // Delete cached thumbnail
            let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let thumbURL = cacheURL.appendingPathComponent(item.filename + ".thumb.jpg")
            try? fileManager.removeItem(at: thumbURL)
        } catch {
            print("Error deleting media: \(error)")
        }
    }
    
    // MARK: - Photo Library Import
    
    func importFromPhotoLibrary(results: [PHPickerResult]) {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let targetURL = isDecoyMode ? documentsURL.appendingPathComponent("decoy") : documentsURL
        
        for result in results {
            let provider = result.itemProvider
            
            // Try GIF first
            if provider.hasItemConformingToTypeIdentifier("com.compuserve.gif") {
                provider.loadDataRepresentation(forTypeIdentifier: "com.compuserve.gif") { [weak self] data, error in
                    guard let data = data else { return }
                    let filename = "imported_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999)).gif"
                    let destURL = targetURL.appendingPathComponent(filename)
                    try? data.write(to: destURL)
                    DispatchQueue.main.async {
                        self?.scanDocumentsDirectory()
                    }
                }
            }
            // Try video
            else if provider.hasItemConformingToTypeIdentifier("public.movie") {
                provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { [weak self] url, error in
                    guard let url = url else { return }
                    let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
                    let filename = "imported_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999)).\(ext)"
                    let destURL = targetURL.appendingPathComponent(filename)
                    try? FileManager.default.copyItem(at: url, to: destURL)
                    DispatchQueue.main.async {
                        self?.scanDocumentsDirectory()
                    }
                }
            }
            // Try image
            else if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadDataRepresentation(forTypeIdentifier: "public.image") { [weak self] data, error in
                    guard let data = data else { return }
                    // Detect if it's HEIC/PNG/JPG
                    var ext = "jpg"
                    if provider.hasItemConformingToTypeIdentifier("public.png") { ext = "png" }
                    else if provider.hasItemConformingToTypeIdentifier("public.heic") { ext = "heic" }
                    let filename = "imported_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999)).\(ext)"
                    let destURL = targetURL.appendingPathComponent(filename)
                    try? data.write(to: destURL)
                    DispatchQueue.main.async {
                        self?.scanDocumentsDirectory()
                    }
                }
            }
        }
    }
}
