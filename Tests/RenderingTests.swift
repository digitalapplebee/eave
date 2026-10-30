import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import EaveCore

enum Fixtures {
    static func options(scaling: Int = 3, clips: Bool = true, fill: NSColor = .black) throws -> WallpaperOptions {
        try WallpaperOptions([.imageScaling: scaling, .allowClipping: clips, .fillColor: fill])
    }
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EaveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func image(_ url: URL, width: Int = 40, height: Int = 20,
                      color: EaveCore.RGBColor = .white, type: UTType = .png, frames: Int = 1,
                      properties: [CFString: Any] = [:]) throws {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(color.nsColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil))
        for _ in 0..<frames { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
        #expect(CGImageDestinationFinalize(destination))
    }

    static func pixel(_ url: URL, x: Int, row: Int) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let start = (row * image.width + x) * 4
        return Array(UnsafeBufferPointer(start: data + start, count: 4))
    }
}

struct RenderingTests {
    @Test func retinaNotchAndSecondaryGeometry() {
        let builtIn = DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), scale: 2, safeTop: 38, menuBarHeight: 22, visibleTop: 40)
        #expect(builtIn.width == 3600)
        #expect(builtIn.height == 2338)
        #expect(builtIn.bandHeight == 80)
        let external = DisplayGeometry(frame: CGRect(x: -1920, y: 700, width: 1920, height: 1080), scale: 1, safeTop: 0, menuBarHeight: 24)
        #expect(external.bandHeight == 24)
        #expect(external.width == 1920)
        #expect(external.height == 1080)
    }

    @Test func scalingModes() {
        let image = CGSize(width: 200, height: 100), canvas = CGSize(width: 100, height: 100)
        #expect(ImagePlacement.rect(image: image, canvas: canvas, scaling: 3, clips: false) == CGRect(x: 0, y: 25, width: 100, height: 50))
        #expect(ImagePlacement.rect(image: image, canvas: canvas, scaling: 3, clips: true) == CGRect(x: -50, y: 0, width: 200, height: 100))
        #expect(ImagePlacement.rect(image: image, canvas: canvas, scaling: 1, clips: false) == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(ImagePlacement.rect(image: image, canvas: canvas, scaling: 2, clips: false) == CGRect(x: -50, y: 0, width: 200, height: 100))
    }

    @Test @MainActor func bandOpacityCachingAndOriginalIntegrity() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let bytes = try Data(contentsOf: original)
        let renderer = WallpaperRenderer(directory: directory.appendingPathComponent("Generated"))
        let options = try Fixtures.options(scaling: 1, clips: false)
        let geometry = DisplayGeometry(frame: CGRect(x: -300, y: -800, width: 40, height: 20), scale: 1, safeTop: 0, menuBarHeight: 4)
        let request = RenderRequest(source: original, geometry: geometry, options: options, style: BandStyle(color: .black, opacity: 1))
        let output = try await renderer.render(request)
        #expect(try Fixtures.pixel(output, x: 20, row: 0) == [0, 0, 0, 255])
        #expect(try Fixtures.pixel(output, x: 20, row: 3) == [0, 0, 0, 255])
        #expect(try Fixtures.pixel(output, x: 20, row: 4) == [255, 255, 255, 255])
        #expect(try Fixtures.pixel(output, x: 20, row: 19) == [255, 255, 255, 255])
        #expect(try await renderer.render(request) == output)
        let translucent = try await renderer.render(RenderRequest(source: original, geometry: geometry, options: options,
                                                                 style: BandStyle(color: .black, opacity: 0.5)))
        let pixel = try Fixtures.pixel(translucent, x: 20, row: 0)
        #expect((126...129).contains(Int(pixel[0])))
        #expect(pixel[0] == pixel[1] && pixel[1] == pixel[2])
        #expect(try Data(contentsOf: original) == bytes)
    }

    @Test @MainActor func fitFillAndLetterboxPixels() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("wide.png")
        try Fixtures.image(original, width: 40, height: 10)
        let geometry = DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 40, height: 40), scale: 1, safeTop: 0, menuBarHeight: 2)
        let renderer = WallpaperRenderer(directory: directory.appendingPathComponent("Generated"))
        let fit = try await renderer.render(RenderRequest(source: original, geometry: geometry,
                                                         options: WallpaperOptions([.imageScaling: 3, .allowClipping: false, .fillColor: NSColor.red]),
                                                         style: BandStyle(color: .black, opacity: 1)))
        #expect(try Fixtures.pixel(fit, x: 20, row: 5) == [255, 0, 0, 255])
        #expect(try Fixtures.pixel(fit, x: 20, row: 20) == [255, 255, 255, 255])
        let fill = try await renderer.render(RenderRequest(source: original, geometry: geometry,
                                                          options: Fixtures.options(),
                                                          style: BandStyle(color: .black, opacity: 1)))
        #expect(try Fixtures.pixel(fill, x: 20, row: 5) == [255, 255, 255, 255])
    }

    @Test func missingUnsupportedAndDynamicSources() throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.png")
        #expect(throws: EaveError.missingFile("missing.png")) { try WallpaperRenderer.validateSource(missing) }
        let text = directory.appendingPathComponent("fake.png")
        try Data("not an image".utf8).write(to: text)
        #expect(throws: EaveError.self) { try WallpaperRenderer.validateSource(text) }
        let dynamic = directory.appendingPathComponent("dynamic.tiff")
        try Fixtures.image(dynamic, type: .tiff, frames: 2)
        #expect(throws: EaveError.self) { try WallpaperRenderer.validateSource(dynamic) }
    }

    @Test(arguments: [1.0, 2.0])
    func onlyPlausibleMenuGeometryIsAccepted(scale: Double) {
        let frame = CGRect(x: -1920, y: -1080, width: 1800, height: 1169)
        let geometry = DisplayGeometry(frame: frame, scale: scale, safeTop: 38, menuBarHeight: 22, visibleTop: 219)
        #expect(geometry.bandHeight == Int(38 * scale))
        #expect(geometry.bandRect == CGRect(x: 0, y: Int(1169 * scale) - Int(38 * scale), width: Int(1800 * scale), height: Int(38 * scale)))
        let converted = geometry.quartzRect(fromTopLeft: CGRect(x: 5, y: 10, width: 20, height: 30))
        #expect(converted == CGRect(x: 5, y: geometry.height - 40, width: 20, height: 30))
        let hidden = DisplayGeometry(frame: frame, scale: scale, safeTop: 38, menuBarHeight: 22, visibleTop: 0)
        #expect(hidden.bandHeight == Int(38 * scale))
        #expect(!DisplayGeometry(frame: frame, scale: .infinity, safeTop: 38, menuBarHeight: 22).isValid)
    }

    @Test @MainActor func incompleteLayoutNeverCreatesGuessedBlackLetterboxing() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("wide.png")
        try Fixtures.image(original, width: 410, height: 216)
        let renderer = WallpaperRenderer(directory: directory.appendingPathComponent("Generated"))
        let geometry = DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 360, height: 234), scale: 1, safeTop: 0, menuBarHeight: 8)
        let incomplete = try WallpaperOptions([:])
        await #expect(throws: EaveError.unknownPlacement) {
            try await renderer.render(RenderRequest(source: original, geometry: geometry, options: incomplete, style: BandStyle(color: .black, opacity: 1)))
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("Generated").path))
        let output = try await renderer.render(RenderRequest(source: original, geometry: geometry, options: Fixtures.options(), style: BandStyle(color: .black, opacity: 1)))
        for row in geometry.bandHeight..<geometry.height {
            #expect(try Fixtures.pixel(output, x: geometry.width / 2, row: row) == [255, 255, 255, 255])
        }
    }

    @Test func legacyGuessedOptionsAreNotTrusted() throws {
        let options = try WallpaperOptions([:])
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(options)) as? [String: Any])
        json["scaling"] = 3
        json["clips"] = false
        json["fill"] = ["red": 0, "green": 0, "blue": 0]
        let decoded = try JSONDecoder().decode(WallpaperOptions.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.scaling == nil)
        #expect(throws: EaveError.unknownPlacement) { try decoded.placement() }
    }

    @Test @MainActor func centeredRetinaImageUsesLogicalSizeFromDPI() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("retina.tiff")
        try Fixtures.image(original, width: 20, height: 10, type: .tiff,
                           properties: [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144])
        let info = try WallpaperSource.inspect(original)
        #expect(info.pointSize == CGSize(width: 10, height: 5))
        let renderer = WallpaperRenderer(directory: directory.appendingPathComponent("Generated"))
        let output = try await renderer.render(RenderRequest(source: original,
            geometry: DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 40, height: 30), scale: 2, safeTop: 0, menuBarHeight: 4),
            options: Fixtures.options(scaling: 2, fill: .red), style: BandStyle(color: .black, opacity: 1)))
        #expect(try Fixtures.pixel(output, x: 40, row: 29) == [255, 255, 255, 255])
        #expect(try Fixtures.pixel(output, x: 20, row: 29) == [255, 0, 0, 255])
    }

    @Test @MainActor func orientedImageAndPixelsBelowBandArePreserved() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("oriented.tiff")
        let context = try #require(CGContext(data: nil, width: 20, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 20, width: 20, height: 20))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(original as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        #expect(try WallpaperSource.inspect(original).pixelSize == CGSize(width: 40, height: 20))
        let renderer = WallpaperRenderer(directory: directory.appendingPathComponent("Generated"))
        let output = try await renderer.render(RenderRequest(source: original,
            geometry: DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 40, height: 20), scale: 1, safeTop: 0, menuBarHeight: 4),
            options: Fixtures.options(), style: BandStyle(color: .black, opacity: 1)))
        #expect(try Fixtures.pixel(output, x: 5, row: 0) == [0, 0, 0, 255])
        #expect(try Fixtures.pixel(output, x: 5, row: 19) == [0, 255, 0, 255])
        #expect(try Fixtures.pixel(output, x: 35, row: 19) == [255, 0, 0, 255])
    }

    @Test func systemFallbackAndAliasesAreManagedEvenWithOneFrame() throws {
        #expect(WallpaperSource.isManagedURL(URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")))
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let managed = directory.appendingPathComponent("com.apple.wallpaper/poster.png")
        try FileManager.default.createDirectory(at: managed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixtures.image(managed)
        let alias = directory.appendingPathComponent("ordinary.png")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: managed)
        #expect(try WallpaperSource.inspect(managed).kind == .managed)
        #expect(try WallpaperSource.inspect(alias).kind == .managed)
    }
}
