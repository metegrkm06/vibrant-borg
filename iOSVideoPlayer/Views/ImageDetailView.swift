import SwiftUI

struct ImageDetailView: View {
    let images: [MediaItem]
    let startIndex: Int

    @State private var currentIndex: Int = 0
    @State private var showControls: Bool = true
    @Environment(\.presentationMode) var presentationMode

    init(images: [MediaItem], startIndex: Int) {
        self.images = images
        self.startIndex = startIndex
        self._currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            TabView(selection: $currentIndex) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                    ZoomableImageView(item: item)
                        .tag(index)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            .edgesIgnoringSafeArea(.all)

            if showControls {
                VStack {
                    // Top Bar
                    HStack {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .padding()
                        }

                        Spacer()

                        Text(images.indices.contains(currentIndex) ? images[currentIndex].filename : "")
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        // Balancing spacer matching the back button width
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.clear)
                            .padding()
                    }
                    .padding(.top, 44) // Safe area top padding estimate
                    .background(
                        LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.7), Color.clear]), startPoint: .top, endPoint: .bottom)
                            .edgesIgnoringSafeArea(.top)
                    )

                    Spacer()

                    // Bottom Bar
                    if images.indices.contains(currentIndex) {
                        HStack {
                            Spacer()
                            ShareLink(item: images[currentIndex].url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding()
                            }
                        }
                        .padding(.bottom, 34) // Safe area bottom padding estimate
                        .background(
                            LinearGradient(gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                                .edgesIgnoringSafeArea(.bottom)
                        )
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: !showControls)
        .preferredColorScheme(.dark)
    }
}

struct ZoomableImageView: View {
    let item: MediaItem
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        Group {
            if let uiImage = UIImage(contentsOfFile: item.url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                let newScale = scale * delta
                                scale = min(max(newScale, 1.0), 5.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                if scale < 1.0 {
                                    withAnimation {
                                        scale = 1.0
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            scale = scale == 1.0 ? 2.0 : 1.0
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("Image unavailable")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}
