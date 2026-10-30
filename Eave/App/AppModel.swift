import AppKit
import Combine
import EaveCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var settings = EaveSettings() {
        didSet {
            guard settings != oldValue else { return }
            do { try store.save(settings) }
            catch { errorMessage = "Settings could not be saved: \(error.localizedDescription)" }
            if settings.enabled != oldValue.enabled {
                schedule(retry: settings.enabled)
            } else if settings.effect(systemIsDark: systemIsDark) != oldValue.effect(systemIsDark: systemIsDark) {
                schedule(debounce: true)
            }
        }
    }
    @Published private(set) var systemIsDark = false
    @Published var errorMessage: String?
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    private(set) var engine: MenuBarAppearanceEngine?
    private let store = SettingsStore()
    private var instanceLock: InstanceLock?
    private var monitor: SystemEventMonitor?
    private var operation: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var started = false

    init() {
        do {
            let directory = WallpaperRecoveryService.defaultDirectory
            instanceLock = try InstanceLock(directory: directory)
            let recovery = try WallpaperRecoveryService(directory: directory)
            engine = MenuBarAppearanceEngine(recovery: recovery)
            do { settings = try store.load() }
            catch {
                settings = EaveSettings()
                errorMessage = "Preferences could not be read. Eave is disabled so original wallpapers can be restored. Change a setting to save fresh preferences."
            }
            subscription = engine?.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        } catch { errorMessage = error.localizedDescription }
    }

    var effectiveStyle: BandStyle { settings.effect(systemIsDark: systemIsDark) }
    var usesDarkColor: Bool { settings.appearance.usesDarkColor(systemIsDark: systemIsDark) }
    var selection: ColorSelection {
        get { settings.selection(systemIsDark: systemIsDark) }
        set { if usesDarkColor { settings.dark = newValue } else { settings.light = newValue } }
    }
    var statuses: [DisplayStatus] { engine?.statuses ?? [] }
    var isApplying: Bool { engine?.isApplying ?? false }
    var isReady: Bool { engine != nil }

    func start() {
        guard !started else { return }
        started = true
        updateSystemState()
        monitor = SystemEventMonitor(onChange: { [weak self] in
            self?.updateSystemState()
            self?.schedule()
        }, onSleep: { [weak self] in
            self?.operation?.cancel()
            self?.engine?.invalidate()
        })
        schedule()
    }

    private func updateSystemState() {
        systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        loginStatus = SMAppService.mainApp.status
        let registered = loginStatus == .enabled || loginStatus == .requiresApproval
        if settings.launchAtLogin != registered { settings.launchAtLogin = registered }
    }

    func schedule(retry: Bool = false, debounce: Bool = false) {
        operation?.cancel()
        engine?.invalidate()
        operation = Task { [weak self] in
            do { if debounce { try await Task.sleep(for: .milliseconds(220)) } }
            catch { return }
            guard let self, let engine = self.engine else { return }
            await engine.reconcile(settings: self.settings, systemIsDark: self.systemIsDark, retry: retry)
        }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginStatus = SMAppService.mainApp.status
            settings.launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
        } catch { errorMessage = "Launch at Login: \(error.localizedDescription)" }
    }

    func shutdown() -> Bool {
        operation?.cancel()
        guard let engine else { return true }
        let errors = engine.restoreVisible()
        if !errors.isEmpty {
            errorMessage = "Eave stayed open because restoration failed. \(errors.joined(separator: " "))"
            return false
        }
        return true
    }

    func openSystemSettings(_ page: String) {
        if let url = URL(string: "x-apple.systempreferences:\(page)"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model?.start()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.shutdown() == false ? .terminateCancel : .terminateNow
    }
}
