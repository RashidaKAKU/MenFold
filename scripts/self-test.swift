import AppKit
import Foundation

@main
enum SelfTest {
    static func main() throws {
        let first = MenuBarItem.stableIdentifier(
            bundleIdentifier: "com.example.app",
            ownerName: "Example",
            windowName: "Status",
            occurrence: 0
        )
        let second = MenuBarItem.stableIdentifier(
            bundleIdentifier: "com.example.app",
            ownerName: "Example",
            windowName: "Status",
            occurrence: 1
        )
        precondition(first == "com.example.app|Status|0")
        precondition(first != second)
        precondition(MenuBarItem.isTransientBadge(
            bundleIdentifier: "com.tencent.xinWeChat",
            ownerName: "微信",
            windowName: " 12"
        ))
        precondition(!MenuBarItem.isTransientBadge(
            bundleIdentifier: "com.tencent.xinWeChat",
            ownerName: "微信",
            windowName: "微信"
        ))
        precondition(MenuBarItem.isTransientBadgeIdentifier("com.tencent.xinWeChat| 3|0"))

        var preferences = AppPreferences()
        preferences.itemVisibility["sample"] = .hidden
        preferences.foldGroups = [
            FoldGroup(id: "work", name: "工作"),
            FoldGroup(id: "tools", name: "工具")
        ]
        preferences.itemGroupIDs["sample"] = "work"
        preferences.statusContent = .dateAndTime
        precondition(preferences.moveFoldGroup(id: "tools", by: -1))
        precondition(preferences.foldGroups.map(\.id) == ["tools", "work"])
        precondition(!preferences.moveFoldGroup(id: "tools", by: -1))
        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
        precondition(decoded == preferences)

        let legacyData = #"{"itemVisibility":{"legacy":"hidden"},"statusContent":"icon","launchAtLogin":false,"showDashboard":true,"panelWidth":420}"#.data(using: .utf8)!
        let migrated = try JSONDecoder().decode(AppPreferences.self, from: legacyData)
        precondition(migrated.itemVisibility["legacy"] == .hidden)
        precondition(migrated.foldGroups.isEmpty)
        precondition(migrated.itemGroupIDs.isEmpty)
        precondition(migrated.knownItemIDs.isEmpty)
        precondition(migrated.panelAutoCloseEnabled)

        print("MenuFold self-test passed")
    }
}
