import AppKit
import EaveCore
import SwiftUI

@main
enum EntryPoint {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--verify-desktop") {
            DesktopVerification.run()
        } else if CommandLine.arguments.contains("--verify-preservation") {
            PreservationVerification.run()
        } else {
            EaveApp.main()
        }
    }
}

struct EaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        delegate.model = model
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(model: model)
                .onAppear {
                    delegate.model = model
                    model.start()
                    model.schedule()
                }
        } label: {
            Image(systemName: "menubar.rectangle")
                .accessibilityLabel("Eave — menu bar appearance")
                .onAppear {
                    delegate.model = model
                    model.start()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Eave Settings", id: "settings") {
            SettingsView(model: model)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 480, height: 600)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Window("About Eave", id: "about") {
            AboutView()
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 340, height: 260)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

@MainActor
enum DesktopVerification {
    static func run() {
        // This command never swaps dynamic wallpapers for a test fixture.
        do {
            _ = NSApplication.shared
            let directory = WallpaperRecoveryService.defaultDirectory
            let lock = try InstanceLock(directory: directory)
            try withExtendedLifetime(lock) {
                let recovery = try WallpaperRecoveryService(directory: directory)
                let system = AppKitWallpaperSystem()
                let displays = DisplayManager.connected()
                guard !displays.isEmpty else { throw EaveError.noWallpaper }
                for display in displays {
                    let snapshot = try system.snapshot(for: display)
                    let record = recovery.record(for: snapshot.url, displayID: display.id)
                    if recovery.owns(snapshot.url), record == nil { throw EaveError.unknownGeneratedWallpaper }
                    let original = record?.original ?? snapshot.url
                    _ = try WallpaperRenderer.validateSource(original)
                    _ = try (record?.options ?? snapshot.options).placement()
                    guard display.geometry.isValid else { throw EaveError.invalidGeometry }
                }
                print("Preflight passed. Testing the visible desktops; originals are recorded before applying.")
                let engine = MenuBarAppearanceEngine(recovery: recovery, system: system)
                Task { @MainActor in
                    var settings = EaveSettings()
                    settings.enabled = true
                    await engine.reconcile(settings: settings, systemIsDark: false, retry: true)
                    let succeeded = engine.statuses.count == displays.count && engine.statuses.allSatisfy(\.applied)
                    for status in engine.statuses { print("\(status.name): \(status.message)") }
                    let errors = engine.restoreVisible()
                    for error in errors { print("RESTORATION ERROR: \(error)") }
                    print(succeeded && errors.isEmpty ? "PASS: applied black and restored original URLs/options." : "FAIL: inspect the recovery journal.")
                    withExtendedLifetime(lock) { exit(succeeded && errors.isEmpty ? 0 : 1) }
                }
                RunLoop.main.run()
            }
        } catch {
            print("Desktop verification stopped without changing wallpapers: \(error.localizedDescription)")
            exit(2)
        }
    }
}
