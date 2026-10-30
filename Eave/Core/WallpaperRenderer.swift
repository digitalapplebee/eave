import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

public struct RenderRequest: Sendable {
    public let id = UUID()
    public let source: URL
    public let geometry: DisplayGeometry
    public let options: WallpaperOptions
    public let style: BandStyle
    public init(source: URL, geometry: DisplayGeometry, options: WallpaperOptions, style: BandStyle) {
        self.source = source; self.geometry = geometry; self.options = options; self.style = style
    }
}

public protocol WallpaperRendering: Sendable {
    func render(_ request: RenderRequest) async throws -> URL
}

public actor WallpaperRenderer: WallpaperRendering {
    private let directory: URL
    private let images = NSCache<NSString, CGImage>()
    public init(directory: URL) {
        self.directory = directory
        images.totalCostLimit = 128 * 1024 * 1024
    }

    public func render(_ request: RenderRequest) throws -> URL {
        let requestID = request.id.uuidString
        var completed = false
        defer {
            if !completed { Diagnostics.rendering.debug("request=\(requestID, privacy: .public) cancelled-or-failed") }
        }
        try Task.checkCancellation()
        guard request.source.resolvingSymlinksInPath().deletingLastPathComponent() != directory.resolvingSymlinksInPath() else {
            throw EaveError.unknownGeneratedWallpaper
        }
        let sourceInfo = try WallpaperSource.inspect(request.source)
        try sourceInfo.requireStatic()
        let placement = try request.options.placement()
        let properties = try request.source.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let geometry = request.geometry
        guard geometry.isValid, geometry.width <= 16384, geometry.height <= 16384,
              geometry.width * geometry.height <= 80_000_000 else { throw EaveError.invalidGeometry }
        Diagnostics.rendering.debug("request=\(requestID, privacy: .public) type=\(sourceInfo.kind.rawValue, privacy: .public) source=\(sourceInfo.pixelSize.width)x\(sourceInfo.pixelSize.height) output=\(geometry.width)x\(geometry.height) bandPx=\(geometry.bandHeight) mode=\(placement.scaling) clips=\(placement.clips)")
        let version = "\(request.source.path)|\(properties.fileSize ?? 0)|\(properties.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        // Invalidate PNGs produced by the old placement/geometry implementation.
        let signature = "renderer-v2|" + version + "|\(geometry)|\(placement)|\(request.style)"
        let name = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
        let output = directory.appendingPathComponent(name).appendingPathExtension("png")
        if FileManager.default.fileExists(atPath: output.path) {
            completed = true
            Diagnostics.rendering.debug("request=\(requestID, privacy: .public) completed cache-hit")
            return output
        }
        let canvas = CGSize(width: geometry.width, height: geometry.height)
        // Placement is based on the original oriented image, never the rounded
        // thumbnail dimensions. Only Center converts image points to backing pixels.
        let imageSize = placement.scaling == NSImageScaling.scaleNone.rawValue
            ? CGSize(width: sourceInfo.pointSize.width * geometry.scale, height: sourceInfo.pointSize.height * geometry.scale)
            : sourceInfo.pixelSize
        let destinationRect = ImagePlacement.rect(image: imageSize, canvas: canvas, scaling: placement.scaling, clips: placement.clips)
        guard destinationRect.width.isFinite, destinationRect.height.isFinite,
              destinationRect.width > 0, destinationRect.height > 0 else { throw EaveError.renderingFailed }
        let maximum = max(1, Int(min(16384, ceil(max(destinationRect.width, destinationRect.height)))))
        let key = "\(version)|\(maximum)" as NSString
        let image: CGImage
        if let cached = images.object(forKey: key) { image = cached }
        else {
            guard let source = CGImageSourceCreateWithURL(request.source as CFURL, nil) else { throw EaveError.renderingFailed }
            let decode: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceCreateThumbnailWithTransform: true,
                                         kCGImageSourceShouldCacheImmediately: true,
                                         kCGImageSourceThumbnailMaxPixelSize: maximum]
            guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, decode as CFDictionary) else { throw EaveError.renderingFailed }
            image = decoded
            images.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        }
        try Task.checkCancellation()
        let imageSpace = image.colorSpace?.model == .rgb ? image.colorSpace : nil
        guard let space = imageSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: geometry.width, height: geometry.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw EaveError.renderingFailed }
        context.clip(to: CGRect(origin: .zero, size: canvas))
        context.setFillColor(placement.fill.nsColor.cgColor)
        context.fill(CGRect(origin: .zero, size: canvas))
        context.interpolationQuality = .high
        context.draw(image, in: destinationRect)
        context.setFillColor(request.style.color.nsColor.withAlphaComponent(request.style.opacity).cgColor)
        context.fill(geometry.bandRect)
        guard let result = context.makeImage() else { throw EaveError.renderingFailed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw EaveError.renderingFailed }
        CGImageDestinationAddImage(destination, result, nil)
        guard CGImageDestinationFinalize(destination) else { throw EaveError.renderingFailed }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: output)
        completed = true
        Diagnostics.rendering.debug("request=\(requestID, privacy: .public) completed")
        return output
    }

    public static func validateSource(_ url: URL) throws -> URLResourceValues {
        try WallpaperSource.inspect(url).requireStatic()
        return try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
    }
}
