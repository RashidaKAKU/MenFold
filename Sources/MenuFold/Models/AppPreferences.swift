import Foundation

enum StatusContent: String, Codable, CaseIterable, Identifiable {
    case icon
    case time
    case dateAndTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: "仅图标"
        case .time: "时间"
        case .dateAndTime: "日期与时间"
        }
    }
}

struct FoldGroup: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var name: String

    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

struct AppPreferences: Codable, Equatable {
    var itemVisibility: [String: ItemVisibility] = [:]
    var foldGroups: [FoldGroup] = []
    var itemGroupIDs: [String: String] = [:]
    var statusContent: StatusContent = .icon
    var launchAtLogin = false
    var showDashboard = true
    var panelWidth = 420.0
    var panelAutoCloseEnabled = true
    var panelAutoCloseDelay = 2.0
    var knownItemIDs: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case itemVisibility
        case foldGroups
        case itemGroupIDs
        case statusContent
        case launchAtLogin
        case showDashboard
        case panelWidth
        case panelAutoCloseEnabled
        case panelAutoCloseDelay
        case knownItemIDs
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemVisibility = try container.decodeIfPresent(
            [String: ItemVisibility].self,
            forKey: .itemVisibility
        ) ?? [:]
        foldGroups = try container.decodeIfPresent(
            [FoldGroup].self,
            forKey: .foldGroups
        ) ?? []
        itemGroupIDs = try container.decodeIfPresent(
            [String: String].self,
            forKey: .itemGroupIDs
        ) ?? [:]
        statusContent = try container.decodeIfPresent(
            StatusContent.self,
            forKey: .statusContent
        ) ?? .icon
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        showDashboard = try container.decodeIfPresent(Bool.self, forKey: .showDashboard) ?? true
        panelWidth = try container.decodeIfPresent(Double.self, forKey: .panelWidth) ?? 420
        panelAutoCloseEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .panelAutoCloseEnabled
        ) ?? true
        panelAutoCloseDelay = try container.decodeIfPresent(
            Double.self,
            forKey: .panelAutoCloseDelay
        ) ?? 2
        knownItemIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .knownItemIDs
        ) ?? []
    }

    @discardableResult
    mutating func moveFoldGroup(id: String, by offset: Int) -> Bool {
        guard let sourceIndex = foldGroups.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let destinationIndex = sourceIndex + offset
        guard foldGroups.indices.contains(destinationIndex), destinationIndex != sourceIndex else {
            return false
        }
        foldGroups.swapAt(sourceIndex, destinationIndex)
        return true
    }
}
