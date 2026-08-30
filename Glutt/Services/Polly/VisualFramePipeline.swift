import CoreMedia
import UIKit

/// The one place a frame becomes something Polly can be shown.
///
/// Both visual sources have to produce byte-identical output here: the phone
/// camera hands over a rendered `UIImage` from a pixel buffer, a wearable camera hand
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

    /// One context for every frame a wearable camera ever send.
    ///
    /// A `CIContext` owns Metal/GPU caches and is expensive to build. Creating
    /// one per frame is the classic way to make a video pipeline grow without
    /// bound, which is why `PollyCameraController` has held a single shared one
    /// since it was written.
    ///
    /// `CIContext` is documented as thread-safe, so the toolkit's delivery
    /// thread and the main actor can both use this one.
    private static let sharedContext = CIContext(options: [
        // THE important option for a video pipeline. A CIContext caches
        // intermediate buffers between renders by default, which is a win when
        // you render the same image repeatedly and a steady leak when every
        // frame is a new image it has never seen. Nothing here is ever rendered
        // twice, so the cache can only grow.
        .cacheIntermediates: false,
        // Frames arrive off the main thread and nothing waits on them, so let
        // Core Image work at low priority rather than contending with the UI.
        .priorityRequestLow: true,
    ])

    /// Decode a wearable camera frame ourselves rather than calling
    /// `VideoFrame.makeUIImage()`.
    ///
    /// Measured on device, `makeUIImage()` cost about **5.8 MB per frame that
    /// was never returned**: memory climbed from 1178 MB to 2031 MB over 148
    /// frames and the app was killed inside a minute. Admission control,
    /// thumbnailing and an autorelease pool around the call all left that slope
    /// exactly unchanged, which is what pointed at the call itself rather than
    /// at what we did with its result.
    ///
    /// This is the same CIImage -> CGImage -> UIImage path the phone camera has
    /// always used, with the context hoisted out of the per-frame work.
    static func image(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = sharedContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// A small copy for on-screen preview.
    ///
    /// A frame straight from the toolkit is backed by its own buffer, so holding
    /// one to show in a thumbnail keeps a full 504x896 surface alive for as long
    /// as it is on screen. Redrawing it small copies the pixels we actually need
    /// and lets the original go straight back.
    static func thumbnail(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > 0 else { return nil }
        let scale = min(1, maxDimension / largestSide)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The data-URI spelling the Realtime `conversation.item.create` event wants.
    /// Both capture paths built this string by hand; they now share one.
    static func dataURI(for jpeg: Data) -> String {
        "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }
}
