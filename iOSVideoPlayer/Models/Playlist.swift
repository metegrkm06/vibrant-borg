import Foundation

struct Playlist: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var videoFilenames: [String] // Store filenames (URL lastPathComponent) to link to actual video files
    
    init(id: UUID = UUID(), name: String, videoFilenames: [String] = []) {
        self.id = id
        self.name = name
        self.videoFilenames = videoFilenames
    }
}
