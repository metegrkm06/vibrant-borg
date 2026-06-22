import Foundation

struct VideoMetadata: Codable, Equatable {
    var customTitle: String?
    var viewCount: Int
    var bookmarks: [Double]
    
    init(customTitle: String? = nil, viewCount: Int = 0, bookmarks: [Double] = []) {
        self.customTitle = customTitle
        self.viewCount = viewCount
        self.bookmarks = bookmarks
    }
}
