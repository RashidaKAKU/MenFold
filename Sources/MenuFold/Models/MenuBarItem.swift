import AppKit
import Foundation

enum ItemVisibility: String, Codable, CaseIterable, Identifiable {
    case visible
    case collapsed
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visible: "始终显示"
        case .collapsed: "折叠"
        case .hidden: "彻底隐藏"
        }
    }

    var symbol: String {
        switch self {
        case .visible: "eye"
        case .collapsed: "chevron.left.2"
        case .hidden: "eye.slash"
        }
    }
}

struct MenuBarItem: Identifiable, Hashable {
    let id: String
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let bundleIdentifier: String?
    let windowName: String
    let bounds: CGRect
    let displayID: CGDirectDisplayID
    let appIcon: NSImage?

    var displayName: String {
        if windowName.isEmpty || windowName == "菜单栏项目" {
            return ownerName
        }
        return windowName
    }

    var systemSymbolName: String? {
        let value = "\(ownerName) \(windowName)".lowercased()
        if value.contains("wi-fi") || value.contains("wifi") { return "wifi" }
        if value.contains("电池") || value.contains("battery") { return "battery.75percent" }
        if value.contains("控制中心") || value.contains("control center") { return "switch.2" }
        if value.contains("时钟") || value.contains("clock") { return "clock" }
        if value.contains("键盘") || value.contains("input") { return "keyboard" }
        return nil
    }

    var isMovable: Bool {
        let value = "\(ownerName) \(windowName)".lowercased()
        if bundleIdentifier == "com.apple.controlcenter" {
            return !value.contains("时钟")
                && !value.contains("clock")
                && !value.contains("控制中心")
                && !value.contains("control center")
        }
        return true
    }

    static func stableIdentifier(
        bundleIdentifier: String?,
        ownerName: String,
        windowName: String,
        occurrence: Int
    ) -> String {
        let owner = bundleIdentifier ?? ownerName
        let item = windowName.isEmpty ? "item" : windowName
        return "\(owner)|\(item)|\(occurrence)"
    }

    static func isTransientBadge(
        bundleIdentifier: String?,
        ownerName: String,
        windowName: String
    ) -> Bool {
        let owner = "\(bundleIdentifier ?? "") \(ownerName)".lowercased()
        guard owner.contains("wechat") || owner.contains("微信") else { return false }
        let label = windowName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !label.isEmpty && label.allSatisfy { $0.isNumber }
    }

    static func isTransientBadgeIdentifier(_ identifier: String) -> Bool {
        let parts = identifier.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        return isTransientBadge(
            bundleIdentifier: String(parts[0]),
            ownerName: "",
            windowName: String(parts[1])
        )
    }

    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.id == rhs.id && lhs.windowID == rhs.windowID && lhs.bounds == rhs.bounds
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(windowID)
        hasher.combine(bounds.origin.x)
        hasher.combine(bounds.origin.y)
        hasher.combine(bounds.width)
        hasher.combine(bounds.height)
    }
}

struct MenuBarSnapshot: Identifiable {
    let id: String
    let image: NSImage
}
