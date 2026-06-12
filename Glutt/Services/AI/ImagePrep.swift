import UIKit

enum ImagePrep {
    /// Downscale + recompress for vision API calls. 1280px is plenty for
    /// "what food is this" — full-resolution photos just burn tokens and time.
    static func prepareForVision(_ data: Data, maxDimension: CGFloat = 1280) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > 0 else { return nil }

        let scale = min(1, maxDimension / largestSide)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.65)
    }
}
