import SwiftUI

struct ImageGalleryView: View {
    var images: [MediaItem]
    var onDelete: (MediaItem) -> Void
    var onRefresh: () -> Void

    let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 8)
    ]

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if images.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No images found")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(destination: ImageDetailView(images: images, startIndex: index)) {
                                GalleryCell(item: item)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    onDelete(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .refreshable {
                    onRefresh()
                }
            }
        }
        .navigationTitle("Images (\(images.count))")
        .navigationBarTitleDisplayMode(.inline)
        // Ensure the navigation bar is dark mode styled if possible in the host navigation controller
        .preferredColorScheme(.dark)
    }
}

struct GalleryCell: View {
    let item: MediaItem

    var body: some View {
        GeometryReader { geo in
            Group {
                if let thumb = item.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else if let uiImage = UIImage(contentsOfFile: item.url.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color(white: 0.15)
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
