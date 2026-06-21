import AppKit
import CoreGraphics

enum MenuFoldEventMarker {
    static let menuBarMove: Int64 = 0x4D_46_4C_44
}

enum MenuBarMoveSide {
    case left
    case right
}

enum MenuBarItemMover {
    @MainActor
    static func move(
        _ item: MenuBarItem,
        to side: MenuBarMoveSide,
        of dividerFrame: CGRect
    ) async -> Bool {
        guard item.isMovable,
              item.bounds.width > 0,
              item.bounds.height > 0,
              let source = CGEventSource(stateID: .hidSystemState)
        else { return false }

        let start = CGPoint(x: item.bounds.midX, y: item.bounds.midY)
        let end = CGPoint(
            x: side == .left ? dividerFrame.minX : dividerFrame.maxX,
            y: dividerFrame.midY
        )
        let originalMouseLocation = CGEvent(source: nil)?.location

        source.localEventsSuppressionInterval = 0
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        guard let down = mouseEvent(type: .leftMouseDown, location: start, source: source) else {
            return false
        }

        CGAssociateMouseAndMouseCursorPosition(0)
        defer {
            CGAssociateMouseAndMouseCursorPosition(1)
            if let originalMouseLocation { CGWarpMouseCursorPosition(originalMouseLocation) }
        }

        down.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(55))

        for step in 1 ... 10 {
            let fraction = CGFloat(step) / 10
            let location = CGPoint(
                x: start.x + (end.x - start.x) * fraction,
                y: start.y + (end.y - start.y) * fraction
            )
            mouseEvent(type: .leftMouseDragged, location: location, source: source)?
                .post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(16))
        }

        guard let up = mouseEvent(type: .leftMouseUp, location: end, source: source) else {
            return false
        }
        up.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(180))
        return true
    }

    private static func mouseEvent(
        type: CGEventType,
        location: CGPoint,
        source: CGEventSource
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else { return nil }
        event.flags = .maskCommand
        event.setIntegerValueField(
            .eventSourceUserData,
            value: MenuFoldEventMarker.menuBarMove
        )
        return event
    }
}
