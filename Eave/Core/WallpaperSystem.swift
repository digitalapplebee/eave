import AppKit

public enum EaveError: LocalizedError, Equatable {
    case noWallpaper, missingFile(String), unsupportedWallpaper(String), corruptRecovery
    case unknownGeneratedWallpaper, changedDuringRender, renderingFailed, wallpaperNotApplied
    case unknownPlacement, invalidGeometry, pendingSystemChange, unsafeRecovery

    public var errorDescription: String? {
        switch self {
        case .noWallpaper: "macOS did not provide a wallpaper file. Choose a still image in Wallpaper settings."
        case .missingFile(let name): "The wallpaper ‘\(name)’ is unavailable. Reconnect its drive or choose another still image."
        case .unsupportedWallpaper(let reason): "\(reason) Choose a single, local still image in Wallpaper settings, then retry."
        case .corruptRecovery: "The wallpaper recovery journal cannot be read. No wallpapers were changed. Keep the journal and contact support."
        case .unknownGeneratedWallpaper: "This Eave wallpaper has no recovery record. Choose your original wallpaper in System Settings."
        case .changedDuringRender: "The wallpaper changed while Eave was rendering. Your new wallpaper was left untouched. Retry when it has finished changing."
        case .renderingFailed: "Eave could not render the wallpaper. Your original file has not been changed."
        case .wallpaperNotApplied: "macOS did not accept the wallpaper change. Open Wallpaper settings and retry."
        case .unknownPlacement: "macOS did not provide a complete, supported still-wallpaper layout. Your wallpaper was left untouched. Choose a local still image in Wallpaper settings."
        case .invalidGeometry: "The display geometry could not be determined safely. No wallpaper was applied."
        case .pendingSystemChange: "Waiting for macOS to confirm the wallpaper change."
        case .unsafeRecovery: "This older recovery record points to a system wallpaper poster, not a recoverable wallpaper configuration. Choose your original wallpaper in System Settings; Eave will not substitute the poster."
        }
    }
}

public struct WallpaperOptions: Codable, Equatable, Sendable {
    public let archive: Data
    public let scaling: Int?
    public let clips: Bool?
    public let fill: RGBColor?
    fileprivate let hasOnlyPlacementKeys: Bool

    private enum CodingKeys: String, CodingKey { case archive, scaling, clips, fill }

    public init(_ options: [NSWorkspace.DesktopImageOptionKey: Any]) throws {
        self.init(options, archive: try NSKeyedArchiver.archivedData(withRootObject: options, requiringSecureCoding: true))
    }

    private init(_ options: [NSWorkspace.DesktopImageOptionKey: Any], archive: Data) {
        self.archive = archive
        scaling = (options[.imageScaling] as? NSNumber)?.intValue
        clips = (options[.allowClipping] as? NSNumber)?.boolValue
        fill = (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB).map(RGBColor.init)
        hasOnlyPlacementKeys = Set(options.keys).isSubset(of: [.imageScaling, .allowClipping, .fillColor])
    }

    public func dictionary() throws -> [NSWorkspace.DesktopImageOptionKey: Any] {
        try Self.dictionary(from: archive)
    }

    private static func dictionary(from archive: Data) throws -> [NSWorkspace.DesktopImageOptionKey: Any] {
        let classes: [AnyClass] = [NSDictionary.self, NSString.self, NSNumber.self, NSColor.self, NSColorSpace.self, NSData.self, NSArray.self]
        guard let dictionary = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: archive)
                as? [String: Any] else { throw EaveError.corruptRecovery }
        return Dictionary(uniqueKeysWithValues: dictionary.map { (NSWorkspace.DesktopImageOptionKey(rawValue: $0.key), $0.value) })
    }

    public func placement() throws -> WallpaperPlacement {
        // Missing options are not proof of Fit/black: modern providers can return
        // an empty or stale legacy NSWorkspace configuration for an aerial wallpaper.
        guard hasOnlyPlacementKeys, let scaling, [1, 2, 3].contains(scaling), let effectiveClipping, let fill else {
            throw EaveError.unknownPlacement
        }
        return WallpaperPlacement(scaling: scaling, clips: effectiveClipping, fill: fill)
    }

    // AppKit explicitly ignores allowClipping for non-proportional modes and
    // can omit that key in its getter. This is a documented no-op, not a Fit guess.
    fileprivate var effectiveClipping: Bool? { scaling == 1 || scaling == 2 ? false : clips }
    var isComposedLayout: Bool { hasOnlyPlacementKeys && scaling == 1 }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let archive = try container.decode(Data.self, forKey: .archive)
        // Old journals contain guessed scaling/fill fields. The archived API
        // dictionary is authoritative; never turn those guesses into known state.
        self.init(try Self.dictionary(from: archive), archive: archive)
    }
}

public struct WallpaperPlacement: Equatable, Sendable {
    public let scaling: Int
    public let clips: Bool
    public let fill: RGBColor
}

public struct WallpaperSnapshot: Equatable, Sendable {
    public let url: URL
    public let options: WallpaperOptions
    public init(url: URL, options: WallpaperOptions) { self.url = url.standardizedFileURL; self.options = options }
    public func matches(_ other: WallpaperSnapshot) -> Bool {
        url == other.url && options.scaling == other.options.scaling
            && options.effectiveClipping == other.options.effectiveClipping && options.fill == other.options.fill
            && options.hasOnlyPlacementKeys == other.options.hasOnlyPlacementKeys
    }
}

@MainActor
public protocol WallpaperSystem: AnyObject {
    func snapshot(for display: Display) throws -> WallpaperSnapshot
    func apply(_ url: URL, options: WallpaperOptions?, to display: Display) throws
}

@MainActor
public final class AppKitWallpaperSystem: WallpaperSystem {
    public init() {}
    public func snapshot(for display: Display) throws -> WallpaperSnapshot {
        guard let url = NSWorkspace.shared.desktopImageURL(for: display.screen) else { throw EaveError.noWallpaper }
        return WallpaperSnapshot(url: url, options: try WallpaperOptions(NSWorkspace.shared.desktopImageOptions(for: display.screen) ?? [:]))
    }
    public func apply(_ url: URL, options: WallpaperOptions?, to display: Display) throws {
        // Output is already composed at screen aspect ratio. Do not crop the band again.
        let dictionary: [NSWorkspace.DesktopImageOptionKey: Any]
        if let options { dictionary = try options.dictionary() }
        else { dictionary = [.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue, .allowClipping: false, .fillColor: NSColor.black] }
        try NSWorkspace.shared.setDesktopImageURL(url, for: display.screen, options: dictionary)
        // The setter acknowledges the request. Its legacy getter can lag behind;
        // the engine tracks acceptance separately from observed confirmation.
    }
}
