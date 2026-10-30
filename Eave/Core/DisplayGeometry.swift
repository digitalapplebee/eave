import AppKit
import CoreGraphics

public struct DisplayGeometry: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bandHeight: Int
    public let scale: Double

    public init(frame: CGRect, scale: Double, safeTop: Double, menuBarHeight: Double, visibleTop: Double = 0) {
        guard frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0,
              scale.isFinite, scale > 0, menuBarHeight.isFinite, menuBarHeight > 0, menuBarHeight < frame.height,
              safeTop.isFinite, safeTop >= 0, safeTop < frame.height,
              (frame.width * scale).isFinite, frame.width * scale < Double(Int.max),
              (frame.height * scale).isFinite, frame.height * scale < Double(Int.max) else {
            width = 0; height = 0; bandHeight = 0; self.scale = 1
            return
        }
        width = max(1, Int((frame.width * scale).rounded()))
        height = max(1, Int((frame.height * scale).rounded()))
        self.scale = scale
        // All inputs are screen-local AppKit points. visibleFrame excludes other
        // work-area reservations too; never accept it as an unbounded menu height.
        let nativeHeight = max(0, safeTop, menuBarHeight)
        let visibleHeight = visibleTop.isFinite && visibleTop > 0 && visibleTop <= nativeHeight + menuBarHeight ? visibleTop : 0
        bandHeight = min(height, max(1, Int((max(nativeHeight, visibleHeight) * scale).rounded(.up))))
    }

    public var isValid: Bool { width > 0 && height > 0 && bandHeight > 0 && bandHeight < height }
    public var pointSize: CGSize { CGSize(width: Double(width) / scale, height: Double(height) / scale) }

    // The raster uses Quartz's bottom-left pixel origin. UI/image rows are
    // top-left. This is the only conversion boundary for the menu bar rectangle.
    public func quartzRect(fromTopLeft rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: Double(height) - rect.maxY, width: rect.width, height: rect.height)
    }
    public var bandRect: CGRect {
        quartzRect(fromTopLeft: CGRect(x: 0, y: 0, width: width, height: bandHeight))
    }
}

public enum ImagePlacement {
    public static func rect(image: CGSize, canvas: CGSize, scaling: Int, clips: Bool) -> CGRect {
        guard image.width.isFinite, image.height.isFinite, image.width > 0, image.height > 0,
              canvas.width.isFinite, canvas.height.isFinite, canvas.width > 0, canvas.height > 0 else { return .zero }
        let size: CGSize
        switch scaling {
        case Int(NSImageScaling.scaleAxesIndependently.rawValue):
            size = canvas
        case Int(NSImageScaling.scaleNone.rawValue):
            size = image
        default:
            let x = canvas.width / image.width, y = canvas.height / image.height
            var ratio = clips ? max(x, y) : min(x, y)
            if scaling == NSImageScaling.scaleProportionallyDown.rawValue { ratio = min(1, ratio) }
            size = CGSize(width: image.width * ratio, height: image.height * ratio)
        }
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

@MainActor
public struct Display {
    public let id: String
    public let name: String
    public let screen: NSScreen
    public let geometry: DisplayGeometry
}

@MainActor
public enum DisplayManager {
    public static func connected() -> [Display] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
            let id = CFUUIDCreateString(nil, uuid) as String
            // NSStatusBar.thickness is 22 even on a notched display: safeAreaInsets takes precedence.
            return Display(id: id, name: screen.localizedName, screen: screen,
                           geometry: DisplayGeometry(frame: screen.frame, scale: screen.backingScaleFactor,
                                                     safeTop: screen.safeAreaInsets.top,
                                                     menuBarHeight: NSStatusBar.system.thickness,
                                                     visibleTop: screen.frame.maxY - screen.visibleFrame.maxY))
        }
    }
}
