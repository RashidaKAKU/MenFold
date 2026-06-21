import AppKit
import ApplicationServices

enum MenuBarActionService {
    static func ownItemFrame(named expectedName: String) -> CGRect? {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXExtrasMenuBarAttribute as CFString,
            &value
        ) == .success,
              let value
        else { return nil }
        for element in menuBarItems(in: value as! AXUIElement) {
            let name = firstNonemptyAttribute(
                of: element,
                keys: [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
            )
            if name == expectedName { return bounds(of: element) }
        }
        return nil
    }

    static func press(_ item: MenuBarItem) -> Bool {
        guard PermissionService.hasAccessibilityAccess else { return false }
        let application = AXUIElementCreateApplication(item.ownerPID)
        AXUIElementSetMessagingTimeout(application, 0.3)

        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXExtrasMenuBarAttribute as CFString,
            &menuBarValue
        ) == .success,
              let menuBarValue
        else { return false }

        let elements = menuBarItems(in: menuBarValue as! AXUIElement)
        let matched = elements.first { element in
            let name = firstNonemptyAttribute(
                of: element,
                keys: [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
            )
            if !item.windowName.isEmpty { return name == item.windowName }
            guard let bounds = bounds(of: element) else { return false }
            return abs(bounds.midX - item.bounds.midX) < 4
        } ?? (elements.count == 1 ? elements[0] : nil)

        guard let matched else { return false }
        return AXUIElementPerformAction(matched, kAXPressAction as CFString) == .success
    }

    private static func menuBarItems(in root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            if stringAttribute(of: element, key: kAXRoleAttribute) == (kAXMenuBarItemRole as String) {
                result.append(element)
                continue
            }
            guard depth < 3 else { continue }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &value
            ) == .success,
                  let children = value as? [AXUIElement]
            else { continue }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return result
    }

    private static func firstNonemptyAttribute(of element: AXUIElement, keys: [String]) -> String {
        for key in keys {
            let value = stringAttribute(of: element, key: key)
            if !value.isEmpty { return value }
        }
        return ""
    }

    private static func stringAttribute(of element: AXUIElement, key: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else {
            return ""
        }
        return value as? String ?? ""
    }

    private static func bounds(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }
}
