import SwiftUI

struct GifDetailView: View {
    let gifs: [MediaItem]
    let startIndex: Int
    
    @State private var currentIndex: Int
    @State private var showControls = true
    @Environment(\.presentationMode) var presentationMode
    
    init(gifs: [MediaItem], startIndex: Int) {
        self.gifs = gifs
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            TabView(selection: $currentIndex) {
                ForEach(0..<gifs.count, id: \.self) { index in
                    AnimatedGifView(url: gifs[index].url)
                        .tag(index)
                        .onTapGesture {
                            withAnimation {
                                showControls.toggle()
                            }
                        }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .edgesIgnoringSafeArea(.all)
            
            if showControls {
                VStack {
                    HStack {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        Text(gifs[currentIndex].filename)
                            .foregroundColor(.white)
                            .font(.headline)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(16)
                        
                        Spacer()
                        
                        Color.clear.frame(width: 50, height: 50)
                    }
                    .padding(.top, 50)
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
    }
}
