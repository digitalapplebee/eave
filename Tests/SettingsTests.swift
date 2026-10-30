import AppKit
import Testing
@testable import EaveCore

struct SettingsTests {
    @Test func colorConversionAndPresets() {
        #expect(RGBColor(hex: 0x202124).hexString == "#202124")
        #expect(ColorPreset.graphite.color == RGBColor(hex: 0x202124))
        #expect(ColorPreset.custom.color == nil)
        #expect(RGBColor(red: -1, green: 2, blue: .nan) == RGBColor(hex: 0x00FF00))
        #expect(RGBColor(NSColor.white) == .white)
    }

    @Test func appearanceAndNotch() {
        var settings = EaveSettings()
        settings.light.preset = .white
        #expect(settings.effect(systemIsDark: false).color == .white)
        #expect(settings.effect(systemIsDark: true).color == .black)
        settings.appearance = .light
        #expect(settings.effect(systemIsDark: true).color == .white)
        settings.appearance = .dark
        #expect(settings.effect(systemIsDark: false).color == .black)
        settings.opacity = 0.3
        settings.hideNotch = true
        #expect(settings.effect(systemIsDark: false) == BandStyle(color: .black, opacity: 1))
    }

    @Test @MainActor func persistenceRoundTripAndCorruption() throws {
        let suite = "EaveTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        #expect(try store.load() == EaveSettings())
        var settings = EaveSettings()
        settings.enabled = true
        settings.light.preset = .custom
        settings.light.custom = RGBColor(hex: 0xAB1234)
        settings.opacity = 0.42
        settings.launchAtLogin = true
        try store.save(settings)
        #expect(try SettingsStore(defaults: defaults).load() == settings)
        defaults.set(Data("broken".utf8), forKey: "eave.settings.v1")
        #expect(throws: (any Error).self) { try store.load() }
    }
}
