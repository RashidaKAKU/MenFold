import AppKit
import CoreGraphics

enum ScreenCoordinateConverter {
    static func appKitRect(fromQuartz rect: CGRect, displayID: CGDirectDisplayID) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
            return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
        }

        let displayBounds = CGDisplayBounds(displayID)
        return CGRect(
            x: screen.frame.minX + rect.minX - displayBounds.minX,
            y: screen.frame.maxY - (rect.maxY - displayBounds.minY),
            width: rect.width,
            height: rect.height
        )
    }

    static func quartzPoint(fromAppKit point: CGPoint, displayID: CGDirectDisplayID) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            return point
        }
        let displayBounds = CGDisplayBounds(displayID)
        return CGPoint(
            x: displayBounds.minX + point.x - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - point.y
        )
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen {
        NSScreen.screens.first(where: { $0.displayID == displayID })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
