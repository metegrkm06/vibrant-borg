import Foundation
import UIKit

// Represents a local video file with metadata and optional generated thumbnail
struct Video: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    var thumbnail: UIImage?
    let duration: TimeInterval
    let dateAdded: Date
    let fileSize: Int64
    var isFavorite: Bool
    
    // Equatable compliance, matching ID and state changes
    static func == (lhs: Video, rhs: Video) -> Bool {
        return lhs.id == rhs.id && 
               lhs.isFavorite == rhs.isFavorite && 
               (lhs.thumbnail == nil) == (rhs.thumbnail == nil)
    }
}
