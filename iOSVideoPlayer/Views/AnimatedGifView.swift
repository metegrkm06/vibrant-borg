import SwiftUI
import UIKit
import ImageIO

struct AnimatedGifView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return
            }
            
            let count = CGImageSourceGetCount(source)
            var images: [UIImage] = []
            var duration: TimeInterval = 0
            
            for i in 0..<count {
                if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                    images.append(UIImage(cgImage: cgImage))
                    
                    if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                       let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                        
                        if let delayTime = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber {
                            duration += delayTime.doubleValue
                        } else if let delayTime = gifProperties[kCGImagePropertyGIFDelayTime as String] as? NSNumber {
                            duration += delayTime.doubleValue
                        } else {
                            duration += 0.1
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                imageView.animationImages = images
                imageView.animationDuration = duration
                imageView.animationRepeatCount = 0
                imageView.startAnimating()
            }
        }
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        // Updates aren't strictly necessary for a static URL view without changing state
    }
}
