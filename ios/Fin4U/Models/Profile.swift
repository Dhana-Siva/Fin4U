import Foundation
import Observation
import UIKit

/// The owner's name and photo. Both stay on this phone: the name in
/// UserDefaults, the photo as a small JPEG file. Neither is ever sent to the
/// receipt server.
@Observable
final class Profile {
    static let nameKey = "profileName"
    static let photoSide: CGFloat = 512

    var name: String {
        didSet { defaults.set(name, forKey: Self.nameKey) }
    }
    private(set) var photoData: Data?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let photoURL: URL

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        let folder = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.photoURL = folder.appendingPathComponent("profile-photo.jpg")
        self.name = defaults.string(forKey: Self.nameKey) ?? ""
        self.photoData = try? Data(contentsOf: photoURL)
    }

    var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var firstName: String { displayName.split(separator: " ").first.map(String.init) ?? "" }
    var hasPhoto: Bool { photoData != nil }
    var photo: UIImage? { photoData.flatMap(UIImage.init(data:)) }

    /// "Dhana Siva" -> "DS"; one word -> its first letter; nothing -> "".
    var initials: String {
        let words = displayName.split(separator: " ")
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return String(letters).uppercased()
    }

    /// Centre-crops to a square and shrinks, so the stored photo is small
    /// however big the original was. Returns false if the data isn't an image.
    @discardableResult
    func setPhoto(from data: Data) -> Bool {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0,
              let jpeg = Self.squareThumbnail(image).jpegData(compressionQuality: 0.85) else { return false }
        do {
            try jpeg.write(to: photoURL, options: .atomic)
        } catch {
            return false
        }
        photoData = jpeg
        return true
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: photoURL)
        photoData = nil
    }

    static func squareThumbnail(_ image: UIImage) -> UIImage {
        let source = image.size
        let side = min(source.width, source.height)
        let target = min(side, photoSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Draw the original offset so its centre square fills the output.
        let scale = target / side
        let drawSize = CGSize(width: source.width * scale, height: source.height * scale)
        let origin = CGPoint(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2)
        return UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

enum Greeting {
    /// "Good evening, Dhana" -- or just "Fin4U" when no name is set.
    static func title(firstName: String, hour: Int) -> String {
        guard !firstName.isEmpty else { return "Fin4U" }
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        return "\(part), \(firstName)"
    }
}
