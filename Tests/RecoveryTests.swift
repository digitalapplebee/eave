import AppKit
import Testing
@testable import EaveCore

private actor PausedRenderer: WallpaperRendering {
    let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private var pending: CheckedContinuation<URL, Never>?
    private let output: URL
    init(output: URL) {
        let stream = AsyncStream<Void>.makeStream()
        started = stream.stream; signal = stream.continuation; self.output = output
    }
    func render(_ request: RenderRequest) async throws -> URL {
        await withCheckedContinuation { continuation in
            pending = continuation
            signal.yield(())
        }
    }
    func release() { pending?.resume(returning: output); pending = nil; signal.finish() }
}

private actor FirstPausedRenderer: WallpaperRendering {
    let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private let renderer: WallpaperRenderer
    private var pending: CheckedContinuation<Void, Never>?
    private var first = true
    init(directory: URL) {
        renderer = WallpaperRenderer(directory: directory)
        let stream = AsyncStream<Void>.makeStream()
        started = stream.stream; signal = stream.continuation
    }
    func render(_ request: RenderRequest) async throws -> URL {
        let shouldPause = first
        first = false
        let url = try await renderer.render(request)
        if shouldPause {
            await withCheckedContinuation { continuation in pending = continuation; signal.yield(()) }
        }
        return url
    }
    func release() { pending?.resume(); pending = nil; signal.finish() }
}

private struct FailingRenderer: WallpaperRendering {
    func render(_ request: RenderRequest) async throws -> URL { throw EaveError.renderingFailed }
}

@MainActor
private final class FakeWallpaperSystem: WallpaperSystem {
    var wallpapers: [String: WallpaperSnapshot] = [:]
    var applied: [(String, URL)] = []
    var fails = false
    var failsAfterChange = false
    var delaysChanges = false
    var queued: [(String, WallpaperSnapshot)] = []
    var composedOptions: WallpaperOptions?
    var beforeApply: (() throws -> Void)?
    func snapshot(for display: Display) throws -> WallpaperSnapshot {
        try #require(wallpapers[display.id])
    }
    func apply(_ url: URL, options: WallpaperOptions?, to display: Display) throws {
        try beforeApply?()
        if fails { throw EaveError.wallpaperNotApplied }
        let snapshot = WallpaperSnapshot(url: url, options: try options ?? composedOptions ?? Fixtures.options(scaling: 1, clips: false))
        if delaysChanges { queued.append((display.id, snapshot)) }
        else { wallpapers[display.id] = snapshot }
        applied.append((display.id, url))
        if failsAfterChange { failsAfterChange = false; throw EaveError.wallpaperNotApplied }
    }
    func completeLatest() {
        for (id, snapshot) in queued { wallpapers[id] = snapshot }
        queued.removeAll()
    }
    func completeNext() {
        guard !queued.isEmpty else { return }
        let (id, snapshot) = queued.removeFirst()
        wallpapers[id] = snapshot
    }
}

struct RecoveryTests {
    @MainActor private func display(id: String = "A", scale: Double = 1) throws -> Display {
        Display(id: id, name: "Test \(id)", screen: try #require(NSScreen.screens.first),
                geometry: DisplayGeometry(frame: CGRect(x: id == "A" ? 0 : -80, y: 0, width: 80, height: 60),
                                          scale: scale, safeTop: 0, menuBarHeight: 4))
    }

    @Test @MainActor func journalPrecedesApplyAndCrashRecoveryRestoresOptions() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let options = try WallpaperOptions([.imageScaling: 3, .allowClipping: true, .fillColor: NSColor.green])
        let system = FakeWallpaperSystem()
        let display = try display()
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: options)
        let recoveryDirectory = directory.appendingPathComponent("Recovery")
        let recovery = try WallpaperRecoveryService(directory: recoveryDirectory)
        system.beforeApply = {
            let disk = try WallpaperRecoveryService(directory: recoveryDirectory)
            #expect(disk.records.first?.original == original)
            #expect(disk.records.first?.options == options)
        }
        var settings = EaveSettings(); settings.enabled = true
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] })
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.applied == true)
        let output = try #require(system.wallpapers[display.id]?.url)
        #expect(output != original)
        // Simulate process death by constructing fresh services from the on-disk journal.
        system.beforeApply = nil
        let recovered = try WallpaperRecoveryService(directory: recoveryDirectory)
        let relaunched = MenuBarAppearanceEngine(recovery: recovered, system: system, displays: { [display] })
        #expect(relaunched.restoreVisible().isEmpty)
        #expect(system.wallpapers[display.id]?.url == original)
        let restoredOptions = try #require(system.wallpapers[display.id]?.options)
        let restored = try restoredOptions.dictionary()
        #expect((restored[.allowClipping] as? NSNumber)?.boolValue == true)
        #expect((restored[.imageScaling] as? NSNumber)?.intValue == 3)
        #expect(RGBColor(try #require(restored[.fillColor] as? NSColor)) == RGBColor(NSColor.green))
        // Keep old outputs available for invisible Spaces.
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test @MainActor func externalChangeIsNeverRestoredOverAndRequiresRetry() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png"), external = directory.appendingPathComponent("external.png")
        try Fixtures.image(original); try Fixtures.image(external, color: RGBColor(hex: 0xABCDEF))
        let options = try Fixtures.options()
        let display = try display()
        let system = FakeWallpaperSystem()
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: options)
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.count == 1)
        system.wallpapers[display.id] = WallpaperSnapshot(url: external, options: options)
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.count == 1)
        #expect(engine.statuses.first?.applied == false)
        #expect(engine.restoreVisible().isEmpty)
        #expect(system.wallpapers[display.id]?.url == external)
        await engine.reconcile(settings: settings, systemIsDark: false, retry: true)
        #expect(system.applied.count == 2)
        #expect(recovery.records.last?.original == external)
        #expect(engine.restoreVisible().isEmpty)
        #expect(system.wallpapers[display.id]?.url == external)
    }

    @Test @MainActor func multipleDisplaysAndNoRepeatedApply() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let displays = [try display(), try display(id: "B", scale: 2)]
        let system = FakeWallpaperSystem()
        for display in displays { system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: try Fixtures.options()) }
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { displays })
        var settings = EaveSettings(); settings.enabled = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.allSatisfy { $0.applied })
        #expect(system.applied.count == 2)
        #expect(recovery.records.count == 2)
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.count == 2)
        settings.enabled = false
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.count == 4)
        #expect(system.wallpapers.values.allSatisfy { $0.url == original })
    }

    @Test @MainActor func apiFailureAndMissingOriginalDoNotReportSuccess() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let display = try display(), system = FakeWallpaperSystem()
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: try Fixtures.options())
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        system.fails = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.applied == false)
        #expect(system.wallpapers[display.id]?.url == original)
        system.fails = false
        await engine.reconcile(settings: settings, systemIsDark: false)
        try FileManager.default.removeItem(at: original)
        #expect(engine.restoreVisible().count == 1)
        #expect(recovery.records.count == 1)
    }

    @Test @MainActor func corruptJournalAndGeneratedOriginalAreRejected() throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = try WallpaperRecoveryService(directory: directory)
        let generated = recovery.generatedDirectory.appendingPathComponent("owned.png")
        #expect(throws: EaveError.unknownGeneratedWallpaper) {
            try recovery.prepare(displayID: "A", original: generated, options: WallpaperOptions([:]), output: generated)
        }
        try Data("broken".utf8).write(to: directory.appendingPathComponent("recovery.json"))
        #expect(throws: EaveError.corruptRecovery) { try WallpaperRecoveryService(directory: directory) }
    }

    @Test @MainActor func wallpaperChangedDuringRenderingIsNotOverwritten() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png"), external = directory.appendingPathComponent("external.png")
        try Fixtures.image(original); try Fixtures.image(external)
        let display = try display(), system = FakeWallpaperSystem()
        let options = try Fixtures.options()
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: options)
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let renderer = PausedRenderer(output: recovery.generatedDirectory.appendingPathComponent("pending.png"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, renderer: renderer, displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        let task = Task { await engine.reconcile(settings: settings, systemIsDark: false) }
        for await _ in renderer.started { break }
        system.wallpapers[display.id] = WallpaperSnapshot(url: external, options: options)
        await renderer.release()
        await task.value
        #expect(system.applied.isEmpty)
        #expect(engine.statuses.first?.failed == true)
        #expect(recovery.records.isEmpty)
        #expect(system.wallpapers[display.id]?.url == external)
    }

    @Test @MainActor func disablingDuringRenderingPreventsLateApply() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let display = try display(), system = FakeWallpaperSystem()
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: try Fixtures.options())
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let renderer = PausedRenderer(output: recovery.generatedDirectory.appendingPathComponent("pending.png"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, renderer: renderer, displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        let task = Task { await engine.reconcile(settings: settings, systemIsDark: false) }
        for await _ in renderer.started { break }
        #expect(engine.restoreVisible().isEmpty)
        await renderer.release()
        await task.value
        #expect(system.applied.isEmpty)
        #expect(recovery.records.isEmpty)
        #expect(system.wallpapers[display.id]?.url == original)
    }

    @Test @MainActor func cleanupPreservesReferencedOutputsAndUserFiles() throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        try FileManager.default.createDirectory(at: recovery.generatedDirectory, withIntermediateDirectories: true)
        let protected = recovery.generatedDirectory.appendingPathComponent("protected.png")
        let orphan = recovery.generatedDirectory.appendingPathComponent("orphan.png")
        try Fixtures.image(protected); try Fixtures.image(orphan)
        for url in [original, protected, orphan] {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-172_800)], ofItemAtPath: url.path)
        }
        try recovery.prepare(displayID: "A", original: original, options: WallpaperOptions([:]), output: protected)
        try recovery.cleanupUnreferenced(visibleWallpapers: [])
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: protected.path))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test @MainActor func delayedGetterDoesNotCauseRepeatedEnableOrDisable() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let display = try display(), system = FakeWallpaperSystem()
        system.delaysChanges = true
        let originalState = WallpaperSnapshot(url: original, options: try Fixtures.options())
        system.wallpapers[display.id] = originalState
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.pending == true)
        #expect(engine.statuses.first?.failed == false)
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.count == 1)
        system.completeLatest()
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.applied == true)
        #expect(system.applied.count == 1)
        settings.enabled = false
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.pending == true)
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.count == 2)
        system.completeLatest()
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.pending == false)
        #expect(system.wallpapers[display.id]?.matches(originalState) == true)
        #expect(system.applied.count == 2)
    }

    @Test @MainActor func disableSupersedesAnUnconfirmedEnable() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let display = try display(), system = FakeWallpaperSystem()
        system.delaysChanges = true
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: try Fixtures.options())
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        settings.enabled = false
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.count == 2)
        #expect(system.applied.last?.1 == original.standardizedFileURL)
        system.completeLatest()
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.wallpapers[display.id]?.url == original.standardizedFileURL)
        #expect(engine.statuses.first?.failed == false)
    }

    @Test @MainActor func partialApplyFailureRollsBackOnlyOurOutput() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let display = try display(), system = FakeWallpaperSystem()
        system.failsAfterChange = true
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: try Fixtures.options())
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.failed == true)
        #expect(system.wallpapers[display.id]?.url == original.standardizedFileURL)
        #expect(system.applied.count == 2)
        #expect(recovery.records.count == 1)
    }

    @Test @MainActor func managedPosterInLegacyRecoveryIsNeverRestored() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let managed = directory.appendingPathComponent("com.apple.wallpaper/DefaultAerial.png")
        try FileManager.default.createDirectory(at: managed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixtures.image(managed)
        let display = try display(), system = FakeWallpaperSystem()
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        try FileManager.default.createDirectory(at: recovery.generatedDirectory, withIntermediateDirectories: true)
        let output = recovery.generatedDirectory.appendingPathComponent("old-output.png")
        try Fixtures.image(output)
        try recovery.prepare(displayID: display.id, original: managed, options: Fixtures.options(), output: output)
        system.wallpapers[display.id] = WallpaperSnapshot(url: output, options: try Fixtures.options(scaling: 1, clips: false))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] })
        await engine.reconcile(settings: EaveSettings(), systemIsDark: false)
        #expect(engine.statuses.first?.failed == true)
        #expect(system.applied.isEmpty)
        #expect(system.wallpapers[display.id]?.url == output.standardizedFileURL)
        #expect(engine.restoreVisible().count == 1)
    }

    @Test(arguments: ["dynamic", "managed", "unknown", "missing", "inaccessible", "incomplete-layout", "unknown-layout-key"])
    @MainActor func unsupportedWallpapersRemainUntouched(kind: String) async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var source = directory.appendingPathComponent("source.png")
        if kind == "managed" {
            source = directory.appendingPathComponent("com.apple.wallpaper/DefaultAerial.png")
            try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        switch kind {
        case "dynamic": try Fixtures.image(source, type: .tiff, frames: 2)
        case "unknown": try Data("not an image".utf8).write(to: source)
        case "missing": break
        default: try Fixtures.image(source)
        }
        if kind == "inaccessible" { try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: source.path) }
        let display = try display(), system = FakeWallpaperSystem()
        let options: WallpaperOptions
        if kind == "incomplete-layout" { options = try WallpaperOptions([:]) }
        else if kind == "unknown-layout-key" {
            options = try WallpaperOptions([.imageScaling: 3, .allowClipping: true, .fillColor: NSColor.black,
                                           NSWorkspace.DesktopImageOptionKey(rawValue: "UnknownPlacement"): 1])
        } else { options = try Fixtures.options() }
        let original = WallpaperSnapshot(url: source, options: options)
        system.wallpapers[display.id] = original
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.failed == true)
        #expect(system.applied.isEmpty)
        #expect(recovery.records.isEmpty)
        settings.enabled = false
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.isEmpty)
        #expect(system.wallpapers[display.id]?.matches(original) == true)
    }

    @Test(arguments: [false, true])
    @MainActor func tenToggleIntentsFinishWithTheLatestState(finalEnabled: Bool) async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let originalBytes = try Data(contentsOf: original)
        let display = try display(), system = FakeWallpaperSystem()
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: try Fixtures.options())
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let renderer = FirstPausedRenderer(directory: recovery.generatedDirectory)
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, renderer: renderer, displays: { [display] })
        var first = EaveSettings(); first.enabled = true
        let stale = Task { await engine.reconcile(settings: first, systemIsDark: false) }
        for await _ in renderer.started { break }
        var latest = first
        for index in 1...9 {
            latest.enabled = index == 9 ? finalEnabled : index.isMultiple(of: 2)
            await engine.reconcile(settings: latest, systemIsDark: false)
        }
        let appliedBeforeStaleCompletion = system.applied.count
        await renderer.release()
        await stale.value
        #expect(system.applied.count == appliedBeforeStaleCompletion)
        #expect(engine.statuses.first?.applied == finalEnabled)
        #expect((system.wallpapers[display.id]?.url != original.standardizedFileURL) == finalEnabled)
        #expect(recovery.records.allSatisfy { $0.original == original.standardizedFileURL })
        #expect(try Data(contentsOf: original) == originalBytes)
        #expect(engine.restoreVisible().isEmpty)
        #expect(system.wallpapers[display.id]?.url == original.standardizedFileURL)
    }

    @Test @MainActor func latestColorWinsWhenAnOlderRenderFinishesLast() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let display = try display(), system = FakeWallpaperSystem()
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: try Fixtures.options())
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let renderer = FirstPausedRenderer(directory: recovery.generatedDirectory)
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, renderer: renderer, displays: { [display] })
        var initial = EaveSettings(); initial.enabled = true
        let stale = Task { await engine.reconcile(settings: initial, systemIsDark: false) }
        for await _ in renderer.started { break }
        var latest = initial; latest.light.preset = .white
        await engine.reconcile(settings: latest, systemIsDark: false)
        let expected = try #require(system.wallpapers[display.id]?.url)
        await renderer.release()
        await stale.value
        #expect(system.wallpapers[display.id]?.url == expected)
        #expect(system.applied.count == 1)
        #expect(try Fixtures.pixel(expected, x: 10, row: 0) == [255, 255, 255, 255])
        #expect(engine.statuses.first?.applied == true)
    }

    @Test @MainActor func renderFailureRestoresAnExistingEaveOutputSafely() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let display = try display(), system = FakeWallpaperSystem()
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        try FileManager.default.createDirectory(at: recovery.generatedDirectory, withIntermediateDirectories: true)
        let old = recovery.generatedDirectory.appendingPathComponent("old.png")
        try Fixtures.image(old, color: .black)
        try recovery.prepare(displayID: display.id, original: original, options: Fixtures.options(), output: old)
        system.wallpapers[display.id] = WallpaperSnapshot(url: old, options: try Fixtures.options(scaling: 1, clips: false))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, renderer: FailingRenderer(), displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.failed == true)
        #expect(system.wallpapers[display.id]?.url == original.standardizedFileURL)
        #expect(system.applied.count == 1)
        #expect(FileManager.default.fileExists(atPath: old.path))
    }

    @Test @MainActor func externallyChangedLayoutOnSameURLIsPreserved() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let display = try display(), system = FakeWallpaperSystem()
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: try Fixtures.options())
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        let generated = try #require(system.wallpapers[display.id]?.url)
        let external = WallpaperSnapshot(url: generated, options: try Fixtures.options(clips: false, fill: .red))
        system.wallpapers[display.id] = external
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.count == 1)
        settings.enabled = false
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.count == 1)
        #expect(system.wallpapers[display.id]?.matches(external) == true)
        #expect(engine.statuses.first?.failed == true)
    }

    @Test @MainActor func intermediateAcceptedWallpaperIsNotMistakenForExternalChange() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let display = try display(), system = FakeWallpaperSystem()
        system.delaysChanges = true
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: try Fixtures.options())
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        settings.light.preset = .white
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.count == 2)
        let expected = try #require(system.applied.last?.1)
        system.completeNext() // The earlier black request becomes observable first.
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.failed == false)
        #expect(engine.statuses.first?.pending == true)
        #expect(system.applied.count == 2)
        system.completeLatest()
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.applied == true)
        #expect(system.wallpapers[display.id]?.url == expected)
        #expect(system.applied.count == 2)
    }

    @Test @MainActor func composedOutputConfirmationIgnoresInapplicableMatteAndClipping() async throws {
        let directory = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.png")
        try Fixtures.image(original)
        let display = try display(), system = FakeWallpaperSystem()
        system.wallpapers[display.id] = WallpaperSnapshot(url: original, options: try Fixtures.options())
        // Observed NSWorkspace behavior for Stretch: no allowClipping key and
        // the system's existing matte color, although the output is fully opaque.
        system.composedOptions = try WallpaperOptions([.imageScaling: 1, .fillColor: NSColor.blue])
        let recovery = try WallpaperRecoveryService(directory: directory.appendingPathComponent("Recovery"))
        let engine = MenuBarAppearanceEngine(recovery: recovery, system: system, displays: { [display] })
        var settings = EaveSettings(); settings.enabled = true
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(engine.statuses.first?.applied == true)
        #expect(engine.statuses.first?.pending == false)
        #expect(system.applied.count == 1)
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.applied.count == 1)
        settings.enabled = false
        await engine.reconcile(settings: settings, systemIsDark: false)
        #expect(system.wallpapers[display.id]?.url == original.standardizedFileURL)
        #expect(system.applied.count == 2)
    }
}
