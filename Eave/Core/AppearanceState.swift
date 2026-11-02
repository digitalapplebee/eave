public enum AppearanceState: Equatable, Sendable {
    case off, checking, applying, waiting, applied, partiallyApplied, notApplied, restoring, restoreFailed

    public static func resolve(enabled: Bool, isApplying: Bool, statuses: [DisplayStatus]) -> AppearanceState {
        if !enabled {
            if isApplying { return .restoring }
            if statuses.contains(where: \.failed) { return .restoreFailed }
            if statuses.contains(where: { $0.pending || $0.applied }) { return .restoring }
            return .off
        }
        if isApplying { return .applying }
        if statuses.isEmpty { return .checking }
        if statuses.allSatisfy(\.applied) { return .applied }
        if statuses.contains(where: \.applied) { return .partiallyApplied }
        if statuses.contains(where: \.failed) { return .notApplied }
        if statuses.contains(where: \.pending) { return .waiting }
        return .notApplied
    }

    public var title: String {
        switch self {
        case .off: "Off"
        case .checking: "Checking…"
        case .applying: "Applying…"
        case .waiting: "Waiting for macOS"
        case .applied: "Applied"
        case .partiallyApplied: "Partially applied"
        case .notApplied: "Not applied"
        case .restoring: "Restoring…"
        case .restoreFailed: "Restore failed"
        }
    }

    public var previewCaption: String {
        switch self {
        case .off: "Selected style preview · Eave is off"
        case .checking, .applying, .waiting: "Selected style preview · not yet applied"
        case .applied: "Selected style preview"
        case .partiallyApplied: "Preview · applied on some displays"
        case .notApplied: "Preview only · not applied"
        case .restoring: "Preview only · restoring original wallpaper"
        case .restoreFailed: "Preview only · wallpaper restoration failed"
        }
    }
}
