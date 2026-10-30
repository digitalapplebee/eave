import AppKit
import Combine

public struct DisplayStatus: Identifiable {
    public let id: String
    public let name: String
    public let message: String
    public let applied: Bool
    public var failed = false
    public var pending = false
}

@MainActor
public final class MenuBarAppearanceEngine: ObservableObject {
    @Published public private(set) var statuses: [DisplayStatus] = []
    @Published public private(set) var isApplying = false
    public let recovery: WallpaperRecoveryService
    private let system: any WallpaperSystem
    private let renderer: any WallpaperRendering
    private let displays: @MainActor () -> [Display]
    private var revision = 0
    private struct PendingChange {
        let before: WallpaperSnapshot
        let target: WallpaperSnapshot
        let original: WallpaperSnapshot
        let isEffect: Bool
        let intermediates: [WallpaperSnapshot]
        func matchesTarget(_ current: WallpaperSnapshot) -> Bool {
            // Our composed PNG is opaque and covers the whole canvas in Stretch;
            // the system's remembered matte color is irrelevant to its appearance.
            isEffect ? current.url == target.url && current.options.isComposedLayout : current.matches(target)
        }
    }
    private enum Restoration { case unchanged, restored, pending }
    private var lastApplied: [String: WallpaperSnapshot] = [:]
    private var pendingChanges: [String: PendingChange] = [:]
    private var pausedDisplays = Set<String>()

    public init(recovery: WallpaperRecoveryService, system: any WallpaperSystem = AppKitWallpaperSystem(),
                renderer: (any WallpaperRendering)? = nil,
                displays: @escaping @MainActor () -> [Display] = DisplayManager.connected) {
        self.recovery = recovery; self.system = system
        self.renderer = renderer ?? WallpaperRenderer(directory: recovery.generatedDirectory)
        self.displays = displays
    }

    public func invalidate() { revision += 1 }

    public func reconcile(settings: EaveSettings, systemIsDark: Bool, retry: Bool = false) async {
        revision += 1
        let currentRevision = revision
        isApplying = true
        defer { if currentRevision == revision { isApplying = false } }
        if retry { pausedDisplays.removeAll() }
        let displays = displays()
        var next: [DisplayStatus] = []
        for display in displays {
            var attemptedOutput: URL?
            var transactionOriginal: WallpaperSnapshot?
            var initialSnapshot: WallpaperSnapshot?
            var renderInProgress = false
            do {
                try Task.checkCancellation()
                guard currentRevision == revision else { return }
                let before = try system.snapshot(for: display)
                initialSnapshot = before
                observePending(for: display, current: before)
                if !settings.enabled {
                    let result = try restore(display, current: before)
                    pausedDisplays.remove(display.id)
                    next.append(DisplayStatus(id: display.id, name: display.name,
                                              message: result == .pending ? EaveError.pendingSystemChange.localizedDescription : result == .restored ? "Original wallpaper restored" : "Original wallpaper unchanged",
                                              applied: false, pending: result == .pending))
                    continue
                }
                let pending = pendingChanges[display.id]
                if pending == nil, let last = lastApplied[display.id], !last.matches(before),
                   !recovery.owns(before.url) || last.url == before.url {
                    pausedDisplays.insert(display.id)
                    lastApplied.removeValue(forKey: display.id)
                }
                if pausedDisplays.contains(display.id) { throw EaveError.changedDuringRender }
                let record = recovery.record(for: before.url, displayID: display.id)
                if recovery.owns(before.url), record == nil { throw EaveError.unknownGeneratedWallpaper }
                let original = pending?.original.url ?? record?.original ?? before.url
                let options = pending?.original.options ?? record?.options ?? before.options
                guard FileManager.default.isReadableFile(atPath: original.path) else { throw EaveError.missingFile(original.lastPathComponent) }
                let source = try WallpaperSource.inspect(original)
                Diagnostics.wallpaper.debug("display=\(display.id, privacy: .public) points=\(display.geometry.pointSize.width)x\(display.geometry.pointSize.height) pixels=\(display.geometry.width)x\(display.geometry.height) scale=\(display.geometry.scale) bandPx=\(display.geometry.bandHeight) type=\(source.kind.rawValue, privacy: .public) sourcePixels=\(source.pixelSize.width)x\(source.pixelSize.height)")
                try source.requireStatic()
                _ = try options.placement()
                let sourceVersion = try original.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let request = RenderRequest(source: original, geometry: display.geometry, options: options, style: settings.effect(systemIsDark: systemIsDark))
                Diagnostics.wallpaper.debug("display=\(display.id, privacy: .public) request=\(request.id.uuidString, privacy: .public) render-start revision=\(currentRevision)")
                renderInProgress = true
                let output = try await renderer.render(request).standardizedFileURL
                renderInProgress = false
                try Task.checkCancellation()
                guard currentRevision == revision else {
                    Diagnostics.wallpaper.debug("display=\(display.id, privacy: .public) request=\(request.id.uuidString, privacy: .public) stale-render discarded")
                    return
                }
                // The screen may have disappeared while its wallpaper was decoded.
                guard let live = self.displays().first(where: { $0.id == display.id }), live.geometry == display.geometry else {
                    throw EaveError.changedDuringRender
                }
                let now = try system.snapshot(for: live)
                let sourceNow = try original.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let isOurPendingTransition = pending.map { $0.matchesTarget(now) || matchesIntermediate(now, states: $0.intermediates) } ?? false
                guard now.matches(before) || isOurPendingTransition,
                      sourceNow.contentModificationDate == sourceVersion.contentModificationDate,
                      sourceNow.fileSize == sourceVersion.fileSize else { throw EaveError.changedDuringRender }
                if isOurPendingTransition { observePending(for: display, current: now) }
                let outstanding = pendingChanges[display.id]
                var confirmed = true
                if let outstanding, outstanding.isEffect, outstanding.target.url == output {
                    confirmed = false // Accepted by macOS; don't submit the same request again.
                } else if now.url != output || outstanding != nil {
                    try recovery.prepare(displayID: display.id, original: original, options: options, output: output)
                    let originalSnapshot = WallpaperSnapshot(url: original, options: options)
                    transactionOriginal = originalSnapshot
                    attemptedOutput = output
                    confirmed = try submit(output, original: originalSnapshot, before: now, isEffect: true, to: live)
                } else {
                    lastApplied[display.id] = now
                }
                next.append(DisplayStatus(id: display.id, name: display.name,
                                          message: confirmed ? "Color applied to this desktop" : EaveError.pendingSystemChange.localizedDescription,
                                          applied: confirmed, pending: !confirmed))
            } catch is CancellationError {
                Diagnostics.wallpaper.debug("display=\(display.id, privacy: .public) render-cancelled revision=\(currentRevision)")
                return
            }
            catch {
                var message = error.localizedDescription
                // A failing adapter can have changed the desktop before throwing.
                // Roll back only our own attempted output, never a new user choice.
                if let attemptedOutput, let original = transactionOriginal,
                   let current = try? system.snapshot(for: display), current.url == attemptedOutput {
                    do {
                        try WallpaperSource.inspect(original.url).requireStatic()
                        _ = try original.options.placement()
                        let confirmed = try submit(original.url, original: original, before: current, isEffect: false, to: display)
                        if !confirmed { message += " " + EaveError.pendingSystemChange.localizedDescription }
                    } catch { message += " Restoration: " + error.localizedDescription }
                } else if renderInProgress, attemptedOutput == nil, let initialSnapshot,
                          let current = try? system.snapshot(for: display), current.matches(initialSnapshot), recovery.owns(current.url) {
                    // If an update failed, don't leave an old, possibly malformed
                    // Eave output in place when its real still original is recoverable.
                    do {
                        if try restore(display, current: current) == .pending { message += " " + EaveError.pendingSystemChange.localizedDescription }
                    } catch { message += " Restoration: " + error.localizedDescription }
                }
                switch error as? EaveError {
                case .unsupportedWallpaper, .unknownPlacement, .changedDuringRender, .unsafeRecovery:
                    Diagnostics.wallpaper.debug("display=\(display.id, privacy: .public) revision=\(currentRevision) preserved=\(message, privacy: .private)")
                default:
                    Diagnostics.wallpaper.error("display=\(display.id, privacy: .public) revision=\(currentRevision) error=\(message, privacy: .private)")
                }
                next.append(DisplayStatus(id: display.id, name: display.name, message: message, applied: false, failed: true))
            }
        }
        guard currentRevision == revision, !Task.isCancelled else { return }
        statuses = next
        let visible = Set(displays.compactMap { try? system.snapshot(for: $0).url })
        if FileManager.default.fileExists(atPath: recovery.generatedDirectory.path) {
            try? recovery.cleanupUnreferenced(visibleWallpapers: visible)
        }
    }

    @discardableResult
    public func restoreVisible() -> [String] {
        invalidate()
        isApplying = false
        var errors: [String] = []
        for display in displays() {
            do {
                if try restore(display) == .pending { errors.append("\(display.name): \(EaveError.pendingSystemChange.localizedDescription)") }
            }
            catch { errors.append("\(display.name): \(error.localizedDescription)") }
        }
        return errors
    }

    private func restore(_ display: Display, current snapshot: WallpaperSnapshot? = nil) throws -> Restoration {
        let current = try snapshot ?? system.snapshot(for: display)
        observePending(for: display, current: current)
        let pending = pendingChanges[display.id]
        if let pending, !pending.isEffect { return .pending }
        let original: WallpaperSnapshot
        if let record = recovery.record(for: current.url, displayID: display.id) {
            original = WallpaperSnapshot(url: record.original, options: record.options)
        } else if let pending, pending.isEffect, current.matches(pending.before) {
            // A disable must supersede an accepted but not yet visible enable.
            original = pending.original
        } else {
            if recovery.owns(current.url) { throw EaveError.unknownGeneratedWallpaper }
            lastApplied.removeValue(forKey: display.id)
            return .unchanged
        }
        guard !pausedDisplays.contains(display.id) else { throw EaveError.changedDuringRender }
        if let last = lastApplied[display.id], last.url == current.url, !last.matches(current) { throw EaveError.changedDuringRender }
        let source = try WallpaperSource.inspect(original.url)
        guard source.kind == .staticImage else { throw EaveError.unsafeRecovery }
        _ = try original.options.placement()
        let confirmed = try submit(original.url, original: original, before: current, isEffect: false, to: display)
        return confirmed ? .restored : .pending
    }

    private func observePending(for display: Display, current: WallpaperSnapshot) {
        guard let pending = pendingChanges[display.id] else { return }
        if pending.matchesTarget(current) {
            pendingChanges.removeValue(forKey: display.id)
            if pending.isEffect { lastApplied[display.id] = current }
            else { lastApplied.removeValue(forKey: display.id) }
            Diagnostics.wallpaper.debug("display=\(display.id, privacy: .public) change-confirmed effect=\(pending.isEffect)")
        } else if !current.matches(pending.before), !matchesIntermediate(current, states: pending.intermediates) {
            pendingChanges.removeValue(forKey: display.id)
            lastApplied.removeValue(forKey: display.id)
            pausedDisplays.insert(display.id)
            Diagnostics.wallpaper.debug("display=\(display.id, privacy: .public) external-change preserved")
        }
    }

    private func matchesIntermediate(_ current: WallpaperSnapshot, states: [WallpaperSnapshot]) -> Bool {
        states.contains { state in
            current.matches(state) || (current.url == state.url && recovery.owns(current.url) && current.options.isComposedLayout)
        }
    }

    private func submit(_ url: URL, original: WallpaperSnapshot, before: WallpaperSnapshot, isEffect: Bool, to display: Display) throws -> Bool {
        let targetOptions = try isEffect ? WallpaperOptions([.imageScaling: 1, .allowClipping: false, .fillColor: NSColor.black]) : original.options
        let target = WallpaperSnapshot(url: url, options: targetOptions)
        let previous = pendingChanges[display.id]
        let intermediates = (previous?.intermediates ?? []) + (previous.map { [$0.before, $0.target] } ?? [])
        let change = PendingChange(before: before, target: target, original: original, isEffect: isEffect, intermediates: intermediates)
        pendingChanges[display.id] = change
        do { try system.apply(url, options: isEffect ? nil : original.options, to: display) }
        catch { pendingChanges.removeValue(forKey: display.id); throw error }
        if let current = try? system.snapshot(for: display) {
            observePending(for: display, current: current)
            guard change.matchesTarget(current) || current.matches(before) || matchesIntermediate(current, states: intermediates) else { throw EaveError.changedDuringRender }
        }
        let confirmed = pendingChanges[display.id] == nil
        Diagnostics.wallpaper.debug("display=\(display.id, privacy: .public) request-accepted effect=\(isEffect) confirmed=\(confirmed)")
        return confirmed
    }
}
