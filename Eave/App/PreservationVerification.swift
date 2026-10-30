import AppKit
import EaveCore

// A diagnostic for the real current managed wallpaper. Even a regression in the
// engine cannot write to the desktop through this adapter; attempts fail the check.
@MainActor
private final class ReadOnlyWallpaperSystem: WallpaperSystem {
    let system = AppKitWallpaperSystem()
    private(set) var writeAttempts = 0
    func snapshot(for display: Display) throws -> WallpaperSnapshot { try system.snapshot(for: display) }
    func apply(_ url: URL, options: WallpaperOptions?, to display: Display) throws {
        writeAttempts += 1
        throw EaveError.unsupportedWallpaper("Preservation verification blocked a wallpaper write.")
    }
}

@MainActor
enum PreservationVerification {
    static func run() {
        do {
            _ = NSApplication.shared
            let directory = WallpaperRecoveryService.defaultDirectory
            let lock = try InstanceLock(directory: directory)
            let recovery = try WallpaperRecoveryService(directory: directory)
            let system = ReadOnlyWallpaperSystem()
            let displays = DisplayManager.connected()
            guard !displays.isEmpty else { throw EaveError.noWallpaper }
            var originals: [String: WallpaperSnapshot] = [:]
            for display in displays {
                let snapshot = try system.snapshot(for: display)
                let record = recovery.record(for: snapshot.url, displayID: display.id)
                if recovery.owns(snapshot.url), record == nil { throw EaveError.unknownGeneratedWallpaper }
                let source = try WallpaperSource.inspect(record?.original ?? snapshot.url)
                guard source.kind != .staticImage else {
                    throw EaveError.unsupportedWallpaper("Use --verify-desktop to test a supported static wallpaper.")
                }
                originals[display.id] = snapshot
                print("Display \(display.id): type=\(source.kind.rawValue), legacy-output=\(record != nil), points=\(display.geometry.pointSize), pixels=\(display.geometry.width)x\(display.geometry.height), scale=\(display.geometry.scale), band=\(display.geometry.bandHeight)px")
            }
            let engine = MenuBarAppearanceEngine(recovery: recovery, system: system)
            Task { @MainActor in
                var settings = EaveSettings()
                for _ in 0..<10 {
                    settings.enabled.toggle()
                    await engine.reconcile(settings: settings, systemIsDark: false)
                }
                let unchanged = displays.allSatisfy { display in
                    guard let before = originals[display.id], let after = try? system.snapshot(for: display) else { return false }
                    return after.matches(before)
                }
                let passed = unchanged && system.writeAttempts == 0
                print("\(passed ? "PASS" : "FAIL"): ten toggle intents, write attempts=\(system.writeAttempts), current URL/options unchanged=\(unchanged). No desktop writes are permitted by this diagnostic.")
                withExtendedLifetime(lock) { exit(passed ? 0 : 1) }
            }
            RunLoop.main.run()
        } catch {
            print("Preservation verification stopped without desktop writes: \(error.localizedDescription)")
            exit(2)
        }
    }
}
