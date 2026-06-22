import XCTest
@testable import MenuFold

final class MenuFoldTests: XCTestCase {
    func testStableIdentifierDistinguishesRepeatedItems() {
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

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, "com.example.app|Status|0")
    }

    func testWeChatNumericBadgesAreTransient() {
        XCTAssertTrue(MenuBarItem.isTransientBadge(
            bundleIdentifier: "com.tencent.xinWeChat",
            ownerName: "微信",
            windowName: " 12"
        ))
        XCTAssertFalse(MenuBarItem.isTransientBadge(
            bundleIdentifier: "com.tencent.xinWeChat",
            ownerName: "微信",
            windowName: "微信"
        ))
        XCTAssertTrue(MenuBarItem.isTransientBadgeIdentifier("com.tencent.xinWeChat| 3|0"))
    }

    func testPreferencesRoundTrip() throws {
        var preferences = AppPreferences()
        preferences.itemVisibility["sample"] = .hidden
        preferences.foldGroups = [FoldGroup(id: "work", name: "工作")]
        preferences.itemGroupIDs["sample"] = "work"
        preferences.statusContent = .dateAndTime

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertEqual(decoded, preferences)
    }

    func testLegacyPreferencesKeepExistingChoices() throws {
        let data = #"{"itemVisibility":{"legacy":"hidden"},"statusContent":"icon","launchAtLogin":false,"showDashboard":true,"panelWidth":420}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertEqual(decoded.itemVisibility["legacy"], .hidden)
        XCTAssertTrue(decoded.foldGroups.isEmpty)
        XCTAssertTrue(decoded.itemGroupIDs.isEmpty)
        XCTAssertTrue(decoded.knownItemIDs.isEmpty)
        XCTAssertTrue(decoded.panelAutoCloseEnabled)
    }

    func testFoldGroupsCanMoveWithinBounds() {
        var preferences = AppPreferences()
        preferences.foldGroups = [
            FoldGroup(id: "work", name: "工作"),
            FoldGroup(id: "tools", name: "工具")
        ]

        XCTAssertTrue(preferences.moveFoldGroup(id: "tools", by: -1))
        XCTAssertEqual(preferences.foldGroups.map(\.id), ["tools", "work"])
        XCTAssertFalse(preferences.moveFoldGroup(id: "tools", by: -1))
    }
}
