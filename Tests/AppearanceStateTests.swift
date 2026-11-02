import Testing
@testable import EaveCore

struct AppearanceStateTests {
    private func status(_ id: String = "A", applied: Bool = false, failed: Bool = false, pending: Bool = false) -> DisplayStatus {
        DisplayStatus(id: id, name: "Display \(id)", message: "", applied: applied, failed: failed, pending: pending)
    }

    @Test func unsupportedWallpaperDoesNotAppearApplied() {
        let state = AppearanceState.resolve(enabled: true, isApplying: false, statuses: [status(failed: true)])
        #expect(state == .notApplied)
        #expect(state.previewCaption == "Preview only · not applied")
    }

    @Test func emptyDisplayResultsAreNotSuccess() {
        #expect(AppearanceState.resolve(enabled: true, isApplying: false, statuses: []) == .checking)
        #expect(AppearanceState.resolve(enabled: false, isApplying: false, statuses: []) == .off)
    }

    @Test func requestedSettingsDoNotReplaceObservedOutcome() {
        #expect(AppearanceState.resolve(enabled: true, isApplying: false, statuses: [status()]) == .notApplied)
        #expect(AppearanceState.resolve(enabled: true, isApplying: false, statuses: [status(pending: true)]) == .waiting)
        #expect(AppearanceState.resolve(enabled: true, isApplying: false, statuses: [status(applied: true)]) == .applied)
        #expect(AppearanceState.resolve(enabled: true, isApplying: true, statuses: [status(failed: true)]) == .applying)
        #expect(AppearanceState.resolve(enabled: true, isApplying: true, statuses: [status(applied: true)]) == .applying)
    }

    @Test func multipleDisplaysReportPartialApplication() {
        let applied = status(applied: true)
        #expect(AppearanceState.resolve(enabled: true, isApplying: false,
                                       statuses: [applied, status("B", failed: true)]) == .partiallyApplied)
        #expect(AppearanceState.resolve(enabled: true, isApplying: false,
                                       statuses: [applied, status("B", pending: true)]) == .partiallyApplied)
        #expect(AppearanceState.resolve(enabled: true, isApplying: false,
                                       statuses: [applied, status("B", applied: true)]) == .applied)
    }

    @Test func disablingWaitsForRestorationInsteadOfReportingOffImmediately() {
        #expect(AppearanceState.resolve(enabled: false, isApplying: true, statuses: []) == .restoring)
        #expect(AppearanceState.resolve(enabled: false, isApplying: false,
                                       statuses: [status(applied: true)]) == .restoring)
        #expect(AppearanceState.resolve(enabled: false, isApplying: false,
                                       statuses: [status(pending: true)]) == .restoring)
        #expect(AppearanceState.resolve(enabled: false, isApplying: false, statuses: [status()]) == .off)
    }

    @Test func restorationFailureRemainsVisibleAfterToggleIsOff() {
        #expect(AppearanceState.resolve(enabled: false, isApplying: false,
                                       statuses: [status(failed: true)]) == .restoreFailed)
        #expect(AppearanceState.resolve(enabled: false, isApplying: true,
                                       statuses: [status(failed: true)]) == .restoring)
    }
}
