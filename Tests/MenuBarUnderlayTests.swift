import AppKit
import Testing
@testable import EaveCore

@MainActor
private final class UnderlayWallpaperSystem: WallpaperSystem {
    var wallpapers: [String: WallpaperSnapshot] = [:]
    var writes: [(String, URL)] = []

    func snapshot(for display: Display) throws -> WallpaperSnapshot {
        try #require(wallpapers[display.id])
    }

    func apply(_ url: URL, options: WallpaperOptions?, to display: Display) throws {
        writes.append((display.id, url))
        wallpapers[display.id] = WallpaperSnapshot(url: url, options: try options ?? Fixtures.options(scaling: 1, clips: false))
    }
}

@MainActor
private final class UnderlayRenderer: MenuBarUnderlayRendering {
    var isSupported = true
    var active: [String: BandStyle] = [:]
    var appliedIDs: [String] = []
    var failure: EaveError?

    func apply(_ style: BandStyle, to display: Display) throws {
        if let failure { throw failure }
        active[display.id] = style
        appliedIDs.append(display.id)
    }
    func remove(for displayID: String) { active.removeValue(forKey: displayID) }
    func retainDisplays(_ displayIDs: Set<String>) {
        active = active.filter { displayIDs.contains($0.key) }
    }
    func removeAll() { active.removeAll() }
}

@MainActor
private final class ConnectedDisplays {
    var values: [Display]
    init(_ values: [Display]) { self.values = values }
}

struct MenuBarUnderlayTests {
    @MainActor private func display(id: String = "A", scale: Double = 1) throws -> Display {
        Display(id: id, name: "Test \(id)", screen: try #require(NSScreen.screens.first),
                geometry: DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 80, height: 60),
                                          scale: scale, safeTop: 0, menuBarHeight: 4))
    }

    private func confirmedSettings() -> EaveSettings {
        var settings = EaveSettings()
        settings.enabled = true
        settings.transparentMenuBarConfirmed = true
        return settings
    }

    @Test(arguments: [1.0, 2.0])
    func nativeMenuHeightRemainsInPoints(scale: Double) {
        let frame = MenuBarUnderlayGeometry.frame(
            screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            displayBounds: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            menuFrames: [CGRect(x: 0, y: 0, width: 1800, height: 39)],
            safeTop: 38, menuBarHeight: 22, scale: scale)
        #expect(frame == CGRect(x: 0, y: 1130, width: 1800, height: 39))
    }

    @Test func secondaryMenuUsesItsOwnTopLeftDisplayOrigin() {
        let frame = MenuBarUnderlayGeometry.frame(
            screenFrame: CGRect(x: -1920, y: 1169, width: 1920, height: 1080),
            displayBounds: CGRect(x: -1920, y: -1080, width: 1920, height: 1080),
            menuFrames: [CGRect(x: 0, y: 0, width: 1800, height: 39),
                         CGRect(x: -1910, y: -1080, width: 300, height: 24),
                         CGRect(x: -1920, y: -1080, width: 1920, height: 24)],
            safeTop: 0, menuBarHeight: 22, scale: 1)
        #expect(frame == CGRect(x: -1920, y: 2225, width: 1920, height: 24))
    }

    @Test func absentOrUnreasonableMenuBoundsDoNotCreateLargeBands() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let invalid = [CGRect(x: 0, y: 0, width: 1800, height: 219),
                       CGRect(x: 0, y: 30, width: 1800, height: 39),
                       CGRect(x: 0, y: 0, width: 900, height: 39),
                       CGRect(x: 0, y: 0, width: 1800, height: 0)]
        #expect(MenuBarUnderlayGeometry.frame(screenFrame: screen, displayBounds: screen,
                                              menuFrames: [], safeTop: 38, menuBarHeight: 22, scale: 2) == nil)
        #expect(MenuBarUnderlayGeometry.frame(screenFrame: screen, displayBounds: screen,
                                              menuFrames: invalid, safeTop: 38, menuBarHeight: 22, scale: 2) == nil)
        #expect(MenuBarUnderlayGeometry.frame(screenFrame: screen, displayBounds: screen,
                                              menuFrames: invalid + [CGRect(x: 0, y: 0, width: 1800, height: 39)],
                                              safeTop: 38, menuBarHeight: 22, scale: 2)
                == CGRect(x: 0, y: 1130, width: 1800, height: 39))
    }

    @Test @MainActor func confirmedManagedWallpaperIsNeverReplaced() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("com.apple.wallpaper/GoldenGatePoster.png")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixtures.image(source)
        let bytes = try Data(contentsOf: source)
        let display = try display(), system = UnderlayWallpaperSystem(), underlay = UnderlayRenderer()
        let original = WallpaperSnapshot(url: source, options: try WallpaperOptions([:]))
        system.wallpapers[display.id] = original
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] }, underlay: underlay)

        await engine.reconcile(settings: confirmedSettings(), systemIsDark: false)

        #expect(engine.statuses.first?.applied == true)
        #expect(engine.statuses.first?.usesUnderlay == true)
        #expect(underlay.active[display.id] == BandStyle(color: .black, opacity: 1))
        #expect(system.writes.isEmpty)
        #expect(system.wallpapers[display.id]?.matches(original) == true)
        #expect(recovery.records.isEmpty)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test @MainActor func underlayDoesNotNeedToDecodeTheWallpaperFile() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("provider-resource.mov")
        let display = try display(), system = UnderlayWallpaperSystem(), underlay = UnderlayRenderer()
        system.wallpapers[display.id] = WallpaperSnapshot(url: missing, options: try WallpaperOptions([:]))
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] }, underlay: underlay)

        await engine.reconcile(settings: confirmedSettings(), systemIsDark: false)

        #expect(engine.statuses.first?.applied == true)
        #expect(underlay.active[display.id] != nil)
        #expect(system.writes.isEmpty)
        #expect(recovery.records.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test(arguments: [true, false])
    @MainActor func managedWallpaperWithoutSetupNeverAppearsApplied(backendAvailable: Bool) async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("com.apple.wallpaper/poster.png")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixtures.image(source)
        let display = try display(), system = UnderlayWallpaperSystem(), underlay = UnderlayRenderer()
        underlay.isSupported = backendAvailable
        system.wallpapers[display.id] = WallpaperSnapshot(url: source, options: try WallpaperOptions([:]))
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] }, underlay: underlay)
        var settings = EaveSettings(); settings.enabled = true
        // Confirmation also cannot override an unavailable platform backend.
        if !backendAvailable { settings.transparentMenuBarConfirmed = true }

        await engine.reconcile(settings: settings, systemIsDark: false)

        #expect(engine.statuses.first?.applied == false)
        #expect(engine.statuses.first?.failed == true)
        #expect(engine.statuses.first?.requiresMenuSetup == backendAvailable)
        #expect(underlay.appliedIDs.isEmpty)
        #expect(system.writes.isEmpty)
        #expect(recovery.records.isEmpty)
    }

    @Test @MainActor func colorChangesDisableAndQuitNeverWriteTheDesktop() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("provider.heic")
        let display = try display(), system = UnderlayWallpaperSystem(), underlay = UnderlayRenderer()
        let original = WallpaperSnapshot(url: source, options: try WallpaperOptions([:]))
        system.wallpapers[display.id] = original
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] }, underlay: underlay)
        var settings = confirmedSettings()
        await engine.reconcile(settings: settings, systemIsDark: false)
        settings.light.preset = .graphite
        settings.opacity = 0.4
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(underlay.active[display.id] == BandStyle(color: EaveCore.RGBColor(hex: 0x202124), opacity: 0.4))
        settings.hideNotch = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(underlay.active[display.id] == BandStyle(color: .black, opacity: 1))
        settings.enabled = false
        await engine.reconcile(settings: settings, systemIsDark: false)
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(underlay.active.isEmpty)
        #expect(engine.statuses.first?.failed == false)
        settings.enabled = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.restoreVisible().isEmpty)
        #expect(underlay.active.isEmpty)
        #expect(system.writes.isEmpty)
        #expect(system.wallpapers[display.id]?.matches(original) == true)
        #expect(recovery.records.isEmpty)
    }

    @Test @MainActor func disconnectedDisplaysAndSleepRemoveUnderlays() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try display(), second = try display(id: "B", scale: 2)
        let connected = ConnectedDisplays([first, second])
        let system = UnderlayWallpaperSystem(), underlay = UnderlayRenderer()
        for display in connected.values {
            system.wallpapers[display.id] = WallpaperSnapshot(url: directory.appendingPathComponent("\(display.id).heic"), options: try WallpaperOptions([:]))
        }
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { connected.values }, underlay: underlay)
        await engine.reconcile(settings: confirmedSettings(), systemIsDark: false)
        #expect(Set(underlay.active.keys) == Set(["A", "B"]))
        connected.values = [first]
        await engine.reconcile(settings: confirmedSettings(), systemIsDark: false)
        #expect(Set(underlay.active.keys) == Set(["A"]))
        engine.suspend()
        #expect(underlay.active.isEmpty)
        #expect(system.writes.isEmpty)
    }

    @Test @MainActor func failedUpdateRemovesOldPanelAndDoesNotReportSuccess() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let display = try display(), system = UnderlayWallpaperSystem(), underlay = UnderlayRenderer()
        system.wallpapers[display.id] = WallpaperSnapshot(url: directory.appendingPathComponent("provider.heic"), options: try WallpaperOptions([:]))
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] }, underlay: underlay)
        await engine.reconcile(settings: confirmedSettings(), systemIsDark: false)
        underlay.failure = .invalidGeometry
        await engine.reconcile(settings: confirmedSettings(), systemIsDark: false)
        #expect(engine.statuses.first?.applied == false)
        #expect(engine.statuses.first?.failed == true)
        #expect(underlay.active.isEmpty)
        #expect(system.writes.isEmpty)
        #expect(recovery.records.isEmpty)
    }

    @Test @MainActor func hiddenMenuWaitsWithoutLeavingAColoredPanel() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let display = try display(), system = UnderlayWallpaperSystem(), underlay = UnderlayRenderer()
        system.wallpapers[display.id] = WallpaperSnapshot(url: directory.appendingPathComponent("provider.heic"), options: try WallpaperOptions([:]))
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] }, underlay: underlay)
        await engine.reconcile(settings: confirmedSettings(), systemIsDark: false)
        underlay.failure = .menuBarUnavailable
        await engine.reconcile(settings: confirmedSettings(), systemIsDark: false)
        #expect(engine.statuses.first?.pending == true)
        #expect(engine.statuses.first?.failed == false)
        #expect(engine.statuses.first?.applied == false)
        #expect(underlay.active.isEmpty)
        #expect(system.writes.isEmpty)
    }

    @Test @MainActor func safeLegacyWallpaperIsRestoredBeforeSwitchingToUnderlay() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let display = try display(), system = UnderlayWallpaperSystem(), underlay = UnderlayRenderer()
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        try FileManager.default.createDirectory(at: recovery.generatedDirectory, withIntermediateDirectories: true)
        let output = recovery.generatedDirectory.appendingPathComponent("old.png")
        try Fixtures.image(output, color: .black)
        try recovery.prepare(displayID: display.id, original: original, options: Fixtures.options(), output: output)
        system.wallpapers[display.id] = WallpaperSnapshot(url: output, options: try Fixtures.options(scaling: 1, clips: false))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] }, underlay: underlay)

        await engine.reconcile(settings: confirmedSettings(), systemIsDark: false)

        #expect(system.writes.count == 1)
        #expect(system.writes.first?.1 == original.standardizedFileURL)
        #expect(system.wallpapers[display.id]?.url == original.standardizedFileURL)
        #expect(underlay.active[display.id] != nil)
        #expect(engine.statuses.first?.usesUnderlay == true)
        #expect(engine.restoreVisible().isEmpty)
        #expect(system.writes.count == 1)
    }

    @Test @MainActor func unsafeLegacyPosterIsNotSubstitutedDuringModeSwitch() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let poster = directory.appendingPathComponent("com.apple.wallpaper/poster.png")
        try FileManager.default.createDirectory(at: poster.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixtures.image(poster)
        let display = try display(), system = UnderlayWallpaperSystem(), underlay = UnderlayRenderer()
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        try FileManager.default.createDirectory(at: recovery.generatedDirectory, withIntermediateDirectories: true)
        let output = recovery.generatedDirectory.appendingPathComponent("old.png")
        try Fixtures.image(output, color: .black)
        try recovery.prepare(displayID: display.id, original: poster, options: Fixtures.options(), output: output)
        system.wallpapers[display.id] = WallpaperSnapshot(url: output, options: try Fixtures.options(scaling: 1, clips: false))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] }, underlay: underlay)

        await engine.reconcile(settings: confirmedSettings(), systemIsDark: false)

        #expect(engine.statuses.first?.failed == true)
        #expect(engine.statuses.first?.applied == false)
        #expect(underlay.appliedIDs.isEmpty)
        #expect(system.writes.isEmpty)
        #expect(system.wallpapers[display.id]?.url == output.standardizedFileURL)
        #expect(recovery.records.count == 1)
    }

    @Test func earlierPreferencesDecodeWithoutTransparentMenuConfirmation() throws {
        var settings = confirmedSettings()
        settings.light.preset = .graphite
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        object.removeValue(forKey: "transparentMenuBarConfirmed")
        let decoded = try JSONDecoder().decode(EaveSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.transparentMenuBarConfirmed == nil)
        #expect(decoded.enabled == true)
        #expect(decoded.light.preset == .graphite)
    }
}
