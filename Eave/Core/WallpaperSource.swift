import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum WallpaperKind: String, Sendable {
    case staticImage, dynamic, managed, unknown
}

public struct WallpaperSource: Sendable {
    public let kind: WallpaperKind
    public let pixelSize: CGSize
    public let pointSize: CGSize
    public let explanation: String

    public func requireStatic() throws {
        guard kind == .staticImage else { throw EaveError.unsupportedWallpaper(explanation) }
    }

    public static func inspect(_ url: URL) throws -> WallpaperSource {
        guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
            throw EaveError.missingFile(url.lastPathComponent)
        }
        let managed = isManagedURL(url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return WallpaperSource(kind: managed ? .managed : .unknown, pixelSize: .zero, pointSize: .zero,
                                   explanation: "The selected wallpaper is not an identifiable still image.")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Double ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Double ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let swapped = (5...8).contains(orientation)
        let pixels = swapped ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        let dpiX = properties[kCGImagePropertyDPIWidth] as? Double ?? 72
        let dpiY = properties[kCGImagePropertyDPIHeight] as? Double ?? 72
        let points = CGSize(width: pixels.width * 72 / (swapped ? dpiY : dpiX),
                            height: pixels.height * 72 / (swapped ? dpiX : dpiY))
        if managed {
            return WallpaperSource(kind: .managed, pixelSize: pixels, pointSize: points,
                                   explanation: "This is a system-managed wallpaper or fallback poster. Eave cannot preserve its dynamic configuration and leaves it untouched.")
        }
        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let tags = metadata.flatMap { CGImageMetadataCopyTags($0) as? [CGImageMetadataTag] } ?? []
        if CGImageSourceGetCount(source) != 1 || tags.contains(where: {
            (CGImageMetadataTagCopyPrefix($0) as String?)?.lowercased() == "apple_desktop"
                || (CGImageMetadataTagCopyNamespace($0) as String?)?.lowercased().contains("apple.com/desktop") == true
        }) {
            return WallpaperSource(kind: .dynamic, pixelSize: pixels, pointSize: points,
                                   explanation: "Dynamic, Light/Dark and multi-frame wallpapers are not customized; their behavior is preserved.")
        }
        let type = CGImageSourceGetType(source) as String?
        let supported = [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier, UTType.heic.identifier, UTType.heif.identifier]
        guard let type, supported.contains(type), pixels.width > 0, pixels.height > 0,
              points.width.isFinite, points.height.isFinite, points.width > 0, points.height > 0 else {
            return WallpaperSource(kind: .unknown, pixelSize: pixels, pointSize: points,
                                   explanation: "The wallpaper type or image geometry is unknown. Only identifiable local still images can be customized.")
        }
        return WallpaperSource(kind: .staticImage, pixelSize: pixels, pointSize: points, explanation: "Local still image")
    }

    public static func isManagedURL(_ url: URL) -> Bool {
        // Inspect both identities: DefaultDesktop.heic is a one-frame symlink to
        // /System/Library/Wallpapers/.default/DefaultAerial.heic on this macOS.
        [url.path, url.resolvingSymlinksInPath().path].contains { original in
            let path = original.lowercased()
            return path.hasPrefix("/system/library/") || path.hasPrefix("/library/wallpapers/")
                || path.contains("/com.apple.wallpaper") || path.contains("/com.apple.idleassetsd/")
                || path.contains("/wallpaperagent/") || path.contains("/com.apple.mobileassetdesktop/")
                || path.contains(".photoslibrary/") || path.contains("/caches/desktop pictures/")
        }
    }
}
