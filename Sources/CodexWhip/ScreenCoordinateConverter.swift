import AppKit
import CoreGraphics

enum ScreenCoordinateConverter {
    static func quartzPoint(fromAppKitPoint point: CGPoint) -> CGPoint? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let displayID = displayID(for: screen) else {
            return nil
        }

        let displayBounds = CGDisplayBounds(displayID)
        return CGPoint(
            x: displayBounds.minX + point.x - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - point.y
        )
    }

    static func appKitRect(fromQuartzRect rect: CGRect) -> CGRect? {
        guard let screen = screen(containingQuartzPoint: rect.origin),
              let displayID = displayID(for: screen) else {
            return nil
        }

        let displayBounds = CGDisplayBounds(displayID)
        return CGRect(
            x: screen.frame.minX + rect.minX - displayBounds.minX,
            y: screen.frame.maxY - (rect.minY - displayBounds.minY) - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func quartzRect(fromAppKitRect rect: CGRect) -> CGRect? {
        guard let origin = quartzPoint(fromAppKitPoint: CGPoint(x: rect.minX, y: rect.maxY)) else {
            return nil
        }
        return CGRect(origin: origin, size: rect.size)
    }

    private static func screen(containingQuartzPoint point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let displayID = displayID(for: screen) else { return false }
            return CGDisplayBounds(displayID).contains(point)
        }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
