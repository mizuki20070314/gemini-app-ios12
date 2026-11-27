import UIKit

enum ImageUtil {
    static func resizedJPEGData(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.85) -> Data? {
        let size = image.size
        var targetSize = size
        if max(size.width, size.height) > maxDimension {
            let scale = maxDimension / max(size.width, size.height)
            targetSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
