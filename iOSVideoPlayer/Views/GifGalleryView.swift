import SwiftUI

struct GifGalleryView: View {
    let gifs: [MediaItem]
    let onDelete: (MediaItem) -> Void
    let onRefresh: () -> Void
    
    let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 2)
    ]
    
    var body: some View {
        Group {
            if gifs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No GIFs found")
                        .foregroundColor(.gray)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(gifs) { gif in
                            NavigationLink(destination: GifDetailView(gifs: gifs, startIndex: gifs.firstIndex(where: { $0.id == gif.id }) ?? 0)) {
                                GeometryReader { geometry in
                                    if let thumbnail = gif.thumbnail {
                                        Image(uiImage: thumbnail)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                            .clipped()
                                    } else {
                                        Color.gray.opacity(0.3)
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .cornerRadius(8)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onDelete(gif)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .refreshable {
                    onRefresh()
                }
            }
        }
        .navigationTitle("GIFs (\(gifs.count))")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .preferredColorScheme(.dark)
    }
}
