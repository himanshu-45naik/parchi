import AppKit
import ImageIO

enum PhotoError: LocalizedError {
    case unreadable

    var errorDescription: String? { "The file is not an image Parchi can read." }
}

enum PhotoLibrary {
    struct Imported {
        let file: String
        let aspect: Double
    }

    private static let cache = NSCache<NSString, NSImage>()

    /// Copies an image into the library, so the original can be moved or deleted.
    static func importPhoto(from url: URL, into folder: URL) throws -> Imported {
        let aspect = try readAspect(of: url)
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension.lowercased()
        let file = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(file))
        return Imported(file: file, aspect: aspect)
    }

    private static func readAspect(of url: URL) throws -> Double {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0
        else {
            throw PhotoError.unreadable
        }
        // EXIF orientations 5 to 8 are rotated by 90 degrees.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? height / width : width / height
    }

    /// A downsampled image, so that many large photos stay cheap to keep on screen.
    static func image(file: String?, folder: URL, maxPixel: Int) -> NSImage? {
        guard let file else { return nil }
        let key = "\(file)@\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let url = folder.appendingPathComponent(file)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key)
        return image
    }
}
