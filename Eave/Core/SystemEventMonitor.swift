import AppKit

@MainActor
public final class SystemEventMonitor: NSObject {
    private let onChange: @MainActor () -> Void
    private let onSleep: @MainActor () -> Void
    private var appearanceObservation: NSKeyValueObservation?
    public init(onChange: @escaping @MainActor () -> Void, onSleep: @escaping @MainActor () -> Void) {
        self.onChange = onChange; self.onSleep = onSleep
        super.init()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.sessionDidBecomeActiveNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(self, selector: #selector(changed), name: name, object: nil)
        }
        workspace.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSApplication.didBecomeActiveNotification, object: nil)
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.onChange() }
        }
    }
    @objc private func changed(_ notification: Notification) { onChange() }
    @objc private func sleeping(_ notification: Notification) { onSleep() }
    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
