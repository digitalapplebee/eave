import AppKit
import Foundation

public struct RGBColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }

    public static let black = RGBColor(hex: 0)
    public static let white = RGBColor(hex: 0xFFFFFF)
    public var hexString: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()),
               Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    public init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    private static func clamp(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
}

public enum ColorPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case black = "Black", graphite = "Graphite", darkGray = "Dark Gray", gray = "Gray", white = "White", custom = "Custom"
    public var id: String { rawValue }
    public var color: RGBColor? {
        switch self {
        case .black: .black
        case .graphite: RGBColor(hex: 0x202124)
        case .darkGray: RGBColor(hex: 0x333333)
        case .gray: RGBColor(hex: 0x808080)
        case .white: .white
        case .custom: nil
        }
    }
}

public enum AppearanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case system = "Follow System", light = "Light", dark = "Dark"
    public var id: String { rawValue }
    public func usesDarkColor(systemIsDark: Bool) -> Bool {
        switch self {
        case .system: systemIsDark
        case .light: false
        case .dark: true
        }
    }
}

public struct ColorSelection: Codable, Equatable, Sendable {
    public var preset: ColorPreset = .black
    public var custom: RGBColor = RGBColor(hex: 0x526D82)
    public init() {}
    public var color: RGBColor { preset.color ?? custom }
}

public struct EaveSettings: Codable, Equatable, Sendable {
    // First launch never changes the user's wallpaper until enabled.
    public var enabled = false
    public var light = ColorSelection()
    public var dark = ColorSelection()
    public var opacity = 1.0
    public var hideNotch = false
    public var appearance: AppearanceMode = .system
    public var launchAtLogin = false
    public init() {}
    public func selection(systemIsDark: Bool) -> ColorSelection {
        appearance.usesDarkColor(systemIsDark: systemIsDark) ? dark : light
    }
    public func effect(systemIsDark: Bool) -> BandStyle {
        BandStyle(color: hideNotch ? .black : selection(systemIsDark: systemIsDark).color,
                  opacity: hideNotch ? 1 : min(1, max(0, opacity.isFinite ? opacity : 1)))
    }
}

public struct BandStyle: Codable, Equatable, Sendable {
    public let color: RGBColor
    public let opacity: Double
    public init(color: RGBColor, opacity: Double) { self.color = color; self.opacity = opacity }
}

@MainActor
public final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "eave.settings.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() throws -> EaveSettings {
        guard let data = defaults.data(forKey: key) else { return EaveSettings() }
        return try JSONDecoder().decode(EaveSettings.self, from: data)
    }
    public func save(_ settings: EaveSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: key)
    }
}
