import AppKit
import Combine
import ServiceManagement

struct CollapsedItemGroup: Identifiable {
    let id: String
    let name: String
    let items: [MenuBarItem]
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case groups
    case items

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "常规"
        case .groups: "折叠分组"
        case .items: "菜单栏项目"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var items: [MenuBarItem] = []
    @Published private(set) var metrics = SystemMetrics.current()
    @Published private(set) var hasAccessibilityAccess = PermissionService.hasAccessibilityAccess
    @Published private(set) var scanDiagnostic = "尚未扫描"
    @Published private(set) var scanPhase: ScanPhase = .idle
    @Published private(set) var scanProgress = 0.0
    @Published private(set) var scanMessage = "等待扫描"
    @Published private(set) var scanEntries: [ScanDiagnosticEntry] = []
    @Published private(set) var layoutDiagnostic = "尚未整理菜单栏"
    @Published var preferences: AppPreferences
    @Published var searchText = ""
    @Published var newGroupName = ""
    @Published var groupNameDrafts: [String: String] = [:]
    @Published var settingsPage: SettingsPage = .items
    @Published var lastError: String?

    var onItemsChanged: (([MenuBarItem]) -> Void)?
    var onPreferencesChanged: (() -> Void)?
    var onVisibilityChanged: (() -> Void)?
    var onPanelRequested: (() -> Void)?
    var onSettingsRequested: (() -> Void)?

    private let scanner = MenuBarScanner()
    private let store: PreferencesStore
    private var timer: Timer?
    private var scanTask: Task<Void, Never>?

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        var loadedPreferences = store.load()
        let transientIDs = Set(
            loadedPreferences.knownItemIDs.filter(MenuBarItem.isTransientBadgeIdentifier)
                + loadedPreferences.itemVisibility.keys.filter(MenuBarItem.isTransientBadgeIdentifier)
                + loadedPreferences.itemGroupIDs.keys.filter(MenuBarItem.isTransientBadgeIdentifier)
        )
        if !transientIDs.isEmpty {
            loadedPreferences.knownItemIDs.subtract(transientIDs)
            for id in transientIDs {
                loadedPreferences.itemVisibility.removeValue(forKey: id)
                loadedPreferences.itemGroupIDs.removeValue(forKey: id)
            }
            store.save(loadedPreferences)
        }
        preferences = loadedPreferences
    }

    var collapsedItems: [MenuBarItem] {
        items.filter { visibility(for: $0) == .collapsed }
    }

    var obscuredItems: [MenuBarItem] {
        items.filter { visibility(for: $0) != .visible }
    }

    var collapsedItemGroups: [CollapsedItemGroup] {
        var result = preferences.foldGroups.compactMap { group -> CollapsedItemGroup? in
            let groupedItems = collapsedItems.filter { groupID(for: $0) == group.id }
            guard !groupedItems.isEmpty else { return nil }
            return CollapsedItemGroup(id: group.id, name: group.name, items: groupedItems)
        }
        let ungrouped = collapsedItems.filter { groupID(for: $0) == nil }
        if !ungrouped.isEmpty {
            result.append(CollapsedItemGroup(
                id: "MenuFold.Ungrouped",
                name: "未分组",
                items: ungrouped
            ))
        }
        return result
    }

    var filteredItems: [MenuBarItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.ownerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    func start() {
        refreshPermissions()
        scanNow(animated: true)
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanNow(animated: false)
                self?.refreshPermissions()
                self?.metrics = SystemMetrics.current()
            }
        }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        timer?.invalidate()
        timer = nil
    }

    func scanNow(animated: Bool = false) {
        if animated {
            scanTask?.cancel()
            scanPhase = .scanning
            scanProgress = 0.08
            scanMessage = "正在核对系统权限…"
            scanEntries = []

            scanTask = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self.scanProgress = 0.28
                self.scanMessage = "正在读取屏幕窗口层…"

                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self.scanProgress = 0.48
                self.scanMessage = "正在查询辅助功能菜单栏…"

                let result = self.scanner.scan()
                guard !Task.isCancelled else { return }
                self.scanProgress = 0.82
                self.scanMessage = "正在合并并验证扫描结果…"

                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self.applyScanResult(result)
            }
            return
        }

        guard scanPhase != .scanning else { return }
        applyScanResult(scanner.scan())
    }

    private func applyScanResult(_ result: MenuBarScanResult) {
        scanTask = nil
        scanProgress = 1
        scanEntries = result.entries
        scanDiagnostic = "窗口 \(result.totalWindowCount) · 窗口候选 \(result.statusWindowCount) · AX 应用 \(result.accessibilityApplicationCount) · AX 项目 \(result.accessibilityItemCount)"
        if let failure = result.failureMessage {
            scanPhase = .failed
            scanMessage = failure
        } else {
            scanPhase = .completed
            scanMessage = "扫描完成，共识别 \(result.items.count) 个菜单栏项目"
        }
        let scanned = result.items
        classifyNewItems(in: scanned)
        guard scanned != items else { return }
        items = scanned
        onItemsChanged?(scanned)
    }

    private func classifyNewItems(in scanned: [MenuBarItem]) {
        let currentIDs = Set(scanned.map(\.id))
        if preferences.knownItemIDs.isEmpty {
            for item in scanned where storedVisibility(for: item) == nil {
                preferences.itemVisibility[item.id] = .visible
            }
            preferences.knownItemIDs = currentIDs
            store.save(preferences)
            return
        }

        let newItems = scanned.filter { !preferences.knownItemIDs.contains($0.id) }
        guard !newItems.isEmpty else { return }
        for item in newItems {
            preferences.itemVisibility[item.id] = item.isMovable ? .collapsed : .visible
        }
        preferences.knownItemIDs.formUnion(currentIDs)
        store.save(preferences)
    }

    func visibility(for item: MenuBarItem) -> ItemVisibility {
        storedVisibility(for: item) ?? .visible
    }

    private func storedVisibility(for item: MenuBarItem) -> ItemVisibility? {
        if let exact = preferences.itemVisibility[item.id] { return exact }
        let owner = item.bundleIdentifier ?? item.ownerName
        let legacyPrefix = "\(owner)|菜单栏项目|"
        return preferences.itemVisibility.first { key, _ in
            key.hasPrefix(legacyPrefix)
        }?.value
    }

    func setVisibility(_ visibility: ItemVisibility, for item: MenuBarItem) {
        let owner = item.bundleIdentifier ?? item.ownerName
        preferences.itemVisibility.keys
            .filter { $0.hasPrefix("\(owner)|菜单栏项目|") }
            .forEach { preferences.itemVisibility.removeValue(forKey: $0) }
        preferences.itemVisibility[item.id] = visibility
        persistPreferences()
        onVisibilityChanged?()
    }

    func groupID(for item: MenuBarItem) -> String? {
        guard let groupID = preferences.itemGroupIDs[item.id],
              preferences.foldGroups.contains(where: { $0.id == groupID })
        else { return nil }
        return groupID
    }

    @discardableResult
    func addFoldGroup(named rawName: String) -> Bool {
        guard let name = validatedGroupName(rawName) else { return false }
        preferences.foldGroups.append(FoldGroup(name: name))
        persistPreferences()
        return true
    }

    @discardableResult
    func renameFoldGroup(id: String, to rawName: String) -> Bool {
        guard let index = preferences.foldGroups.firstIndex(where: { $0.id == id }),
              let name = validatedGroupName(rawName, excluding: id)
        else { return false }
        preferences.foldGroups[index].name = name
        persistPreferences()
        return true
    }

    func deleteFoldGroup(id: String) {
        preferences.foldGroups.removeAll { $0.id == id }
        preferences.itemGroupIDs = preferences.itemGroupIDs.filter { $0.value != id }
        groupNameDrafts.removeValue(forKey: id)
        persistPreferences()
    }

    func moveFoldGroup(id: String, by offset: Int) {
        guard preferences.moveFoldGroup(id: id, by: offset) else { return }
        persistPreferences()
    }

    func assign(_ item: MenuBarItem, toGroupID groupID: String?) {
        if let groupID,
           preferences.foldGroups.contains(where: { $0.id == groupID }) {
            preferences.itemGroupIDs[item.id] = groupID
        } else {
            preferences.itemGroupIDs.removeValue(forKey: item.id)
        }
        persistPreferences()
    }

    func setStatusContent(_ content: StatusContent) {
        preferences.statusContent = content
        persistPreferences()
    }

    func setShowDashboard(_ enabled: Bool) {
        preferences.showDashboard = enabled
        persistPreferences()
    }

    func setPanelAutoCloseEnabled(_ enabled: Bool) {
        preferences.panelAutoCloseEnabled = enabled
        persistPreferences()
    }

    func setPanelAutoCloseDelay(_ delay: Double) {
        preferences.panelAutoCloseDelay = min(30, max(1, delay))
        persistPreferences()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            preferences.launchAtLogin = enabled
            persistPreferences()
        } catch {
            lastError = "无法更新登录启动：\(error.localizedDescription)"
        }
    }

    func refreshPermissions() {
        hasAccessibilityAccess = PermissionService.hasAccessibilityAccess
    }

    func refreshAfterActivation() {
        refreshPermissions()
        scanNow(animated: true)
    }

    func requestAccessibility() {
        PermissionService.requestAccessibilityAccess()
        refreshPermissions()
    }

    func scanReportText() -> String {
        let details = scanEntries.map {
            "[\($0.accepted ? "接受" : "排除")] \($0.title) | \($0.reason) | \($0.technicalDetail)"
        }.joined(separator: "\n")
        return """
        accessibility=\(hasAccessibilityAccess)
        phase=\(scanPhase.rawValue) progress=\(Int(scanProgress * 100))
        message=\(scanMessage)
        summary=\(scanDiagnostic)
        layout=\(layoutDiagnostic)
        \(details)
        """
    }

    func updateLayoutDiagnostic(_ message: String) {
        layoutDiagnostic = message
    }

    func statusTitle(at date: Date = Date()) -> String {
        switch preferences.statusContent {
        case .icon:
            return ""
        case .time:
            return date.formatted(.dateTime.hour().minute())
        case .dateAndTime:
            return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
        }
    }

    private func persistPreferences() {
        store.save(preferences)
        onPreferencesChanged?()
    }

    private func validatedGroupName(_ rawName: String, excluding groupID: String? = nil) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            lastError = "分组名称不能为空。"
            return nil
        }
        guard !preferences.foldGroups.contains(where: {
            $0.id != groupID && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else {
            lastError = "已经存在名为“\(name)”的分组。"
            return nil
        }
        return name
    }
}

enum ScanPhase: String {
    case idle
    case scanning
    case completed
    case failed

    var title: String {
        switch self {
        case .idle: "等待扫描"
        case .scanning: "正在扫描"
        case .completed: "扫描完成"
        case .failed: "扫描失败"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "pause.circle"
        case .scanning: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }
}
