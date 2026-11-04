import AppKit
import CoreGraphics

@MainActor
public protocol MenuBarUnderlayRendering: AnyObject {
    var isSupported: Bool { get }
    func apply(_ style: BandStyle, to display: Display) throws
    func remove(for displayID: String)
    func retainDisplays(_ displayIDs: Set<String>)
    func removeAll()
}

public enum MenuBarUnderlayGeometry {
    // CG window bounds are global top-left points, not backing pixels. Match
    // them to their CG display before placing a panel in AppKit bottom-left points.
    public static func frame(screenFrame: CGRect, displayBounds: CGRect, menuFrames: [CGRect],
                             safeTop: Double, menuBarHeight: Double, scale: Double) -> CGRect? {
        guard screenFrame.width.isFinite, screenFrame.height.isFinite, screenFrame.minX.isFinite, screenFrame.minY.isFinite,
              displayBounds.width.isFinite, displayBounds.height.isFinite, displayBounds.minX.isFinite, displayBounds.minY.isFinite,
              screenFrame.width > 0, screenFrame.height > 0, displayBounds.width > 0, displayBounds.height > 0,
              scale.isFinite, scale > 0, safeTop.isFinite, safeTop >= 0, menuBarHeight.isFinite, menuBarHeight > 0 else { return nil }
        let tolerance = 1 / scale
        let nativeHeight = max(safeTop, menuBarHeight)
        let ratio = screenFrame.height / displayBounds.height
        let heights = menuFrames.compactMap { rect -> Double? in
            let height = rect.height * ratio
            guard abs(rect.minX - displayBounds.minX) <= tolerance,
                  abs(rect.minY - displayBounds.minY) <= tolerance,
                  abs(rect.width - displayBounds.width) <= tolerance,
                  height.isFinite, height >= nativeHeight - tolerance,
                  height <= nativeHeight + menuBarHeight, height < screenFrame.height else { return nil }
            return height
        }
        guard let height = heights.max() else { return nil }
        return CGRect(x: screenFrame.minX, y: screenFrame.maxY - height, width: screenFrame.width, height: height)
    }
}

@MainActor
public final class MenuBarUnderlay: MenuBarUnderlayRendering {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
        // AppKit otherwise moves even a borderless panel below the menu bar.
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private var panels: [String: Panel] = [:]
    public init() {}
    public var isSupported: Bool {
        if #available(macOS 27, *) { return true }
        return false
    }

    public func apply(_ style: BandStyle, to display: Display) throws {
        guard isSupported else { throw EaveError.menuBarSetupRequired }
        let presentation = NSApp?.currentSystemPresentationOptions ?? []
        guard !presentation.contains(.hideMenuBar), !presentation.contains(.autoHideMenuBar) else {
            remove(for: display.id)
            throw EaveError.menuBarUnavailable
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
              !presentation.contains(.disableMenuBarTransparency) else {
            remove(for: display.id)
            throw EaveError.menuBarTransparencyUnavailable
        }
        guard let number = display.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            throw EaveError.menuBarUnavailable
        }
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let frames = windows.compactMap { item -> CGRect? in
            guard (item[kCGWindowLayer as String] as? Int) == menuLevel,
                  let bounds = item[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
        guard let frame = MenuBarUnderlayGeometry.frame(screenFrame: display.screen.frame,
            displayBounds: CGDisplayBounds(number.uint32Value), menuFrames: frames,
            safeTop: display.screen.safeAreaInsets.top, menuBarHeight: NSStatusBar.system.thickness,
            scale: display.screen.backingScaleFactor) else {
            remove(for: display.id)
            throw EaveError.menuBarUnavailable
        }
        let panel: Panel
        if let existing = panels[display.id] { panel = existing }
        else {
            panel = Panel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: menuLevel - 1)
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            // Let macOS hide the band in Mission Control and restore it afterward.
            panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            panels[display.id] = panel
        }
        panel.isOpaque = style.opacity >= 1
        panel.backgroundColor = style.color.nsColor.withAlphaComponent(style.opacity)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        panel.displayIfNeeded()
        Diagnostics.rendering.debug("display=\(display.id, privacy: .public) transparent-menu frame=\(frame.debugDescription, privacy: .public) level=\(menuLevel - 1) wallpaper unchanged")
    }

    public func remove(for displayID: String) { panels.removeValue(forKey: displayID)?.orderOut(nil) }
    public func retainDisplays(_ displayIDs: Set<String>) {
        for id in Array(panels.keys) where !displayIDs.contains(id) { remove(for: id) }
    }
    public func removeAll() {
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
    }
}
