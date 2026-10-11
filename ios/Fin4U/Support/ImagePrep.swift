import UIKit

/// Shrinks a receipt photo before upload. Camera originals are 12+ MP and
/// several MB; Claude reads receipt text fine at ~2000px, and the backend
/// rejects anything over 5 MB.
enum ImagePrep {
    static let maxSide: CGFloat = 2000
    static let maxBytes = 4_500_000

    static func jpeg(from image: UIImage) -> Data? {
        let resized = resized(image, maxSide: maxSide)
        var quality: CGFloat = 0.8
        while quality >= 0.3 {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.1
        }
        return resized.jpegData(compressionQuality: 0.3)
    }

    /// Redrawing also bakes in the image's orientation, so a sideways-flagged
    /// iPhone photo is upright for the model.
    static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            // White underlay so a transparent PNG doesn't turn black.
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
