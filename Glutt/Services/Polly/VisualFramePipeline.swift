import UIKit

/// The one place a frame becomes something Polly can be shown.
///
/// Both visual sources have to produce byte-identical output here: the phone
/// camera hands over a rendered `UIImage` from a pixel buffer, the glasses hand
/// over one decoded from an H.265 stream, and Polly must not be able to tell
/// which is which. Lifted out of `PollyCameraController.captureFrame()` when the
/// second source arrived.
///
/// Deliberately pure, synchronous and nonisolated. Callers run it off the main
/// actor, where resizing and JPEG encoding belong.
enum VisualFramePipeline {
    /// Downscale so the longest side is at most `maxDimension`, then JPEG at
    /// `quality`. Same `UIGraphicsImageRenderer` approach as
    /// `ImagePrep.prepareForVision`, but taking an image rather than encoded
    /// data, because neither source starts from a JPEG.
    ///
    /// Nil when the image has no area to work with.
    static func prepare(
        _ image: UIImage,
        maxDimension: CGFloat = PollyConfig.frameMaxDimension,
        quality: CGFloat = PollyConfig.frameJPEGQuality
    ) -> Data? {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > 0 else { return nil }

        let scale = min(1, maxDimension / largestSide)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// The data-URI spelling the Realtime `conversation.item.create` event wants.
    /// Both capture paths built this string by hand; they now share one.
    static func dataURI(for jpeg: Data) -> String {
        "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }
}
