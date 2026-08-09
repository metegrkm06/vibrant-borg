import Foundation
import UIKit

/// Represents a local image or GIF file
struct MediaItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let filename: String
    var thumbnail: UIImage?
    let dateAdded: Date
    let fileSize: Int64
    let mediaType: MediaType
    
    enum MediaType: String {
        case image
        case gif
    }
    
    var displayTitle: String {
        return url.deletingPathExtension().lastPathComponent
    }
    
    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        return lhs.id == rhs.id &&
               (lhs.thumbnail == nil) == (rhs.thumbnail == nil)
    }
}
