import Foundation
import UIKit

// Represents a local video file with metadata and optional generated thumbnail
struct Video: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    var customTitle: String?
    var thumbnail: UIImage?
    let duration: TimeInterval
    let dateAdded: Date
    let fileSize: Int64
    var isFavorite: Bool
    var viewCount: Int
    var bookmarks: [Double]
    
    var displayTitle: String {
        return customTitle ?? title
    }
    
    // Equatable compliance, matching ID and state changes
    static func == (lhs: Video, rhs: Video) -> Bool {
        return lhs.id == rhs.id && 
               lhs.isFavorite == rhs.isFavorite && 
               lhs.customTitle == rhs.customTitle &&
               lhs.viewCount == rhs.viewCount &&
               lhs.bookmarks == rhs.bookmarks &&
               (lhs.thumbnail == nil) == (rhs.thumbnail == nil)
    }
}
