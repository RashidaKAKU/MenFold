import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let sectionManager: MenuBarSectionManager
    private let panelController: ExpandedPanelController
    private let settingsController: SettingsWindowController
    private let statusItem: NSStatusItem
    private var clockTimer: Timer?
    private var hasScheduledInitialReconcile = false

    init(model: AppModel) {
        self.model = model
        sectionManager = MenuBarSectionManager()
        panelController = ExpandedPanelController(model: model)
        settingsController = SettingsWindowController(model: model)
        statusItem = Self.makeStatusItem()
        super.init()

        configureStatusItem()
        connectModel()
        panelController.onActivate = { [weak self] item in self?.activate(item) }
    }

    private static func makeStatusItem() -> NSStatusItem {
        let autosaveName = "MenuFold.Main"
        let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(CGFloat(0), forKey: positionKey)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        return item
    }

    func start() {
        model.start()
        updateStatusItem()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
    }

    func stop() {
        clockTimer?.invalidate()
        model.stop()
        panelController.stop()
        sectionManager.stop()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func runSmokeTest(completion: @escaping (Bool) -> Void) {
        panelController.show(relativeTo: statusItem.button)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            let panelOpened = self.panelController.isVisible
            self.panelController.simulateFocusLossForTesting()
            let expectsAutoClose = self.model.preferences.panelAutoCloseEnabled
            let closeDelay = expectsAutoClose
                ? self.model.preferences.panelAutoCloseDelay + 0.4
                : 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay) {
                let autoClosePassed = expectsAutoClose
                    ? !self.panelController.isVisible
                    : self.panelController.isVisible
                self.panelController.close()
                completion(panelOpened && autoClosePassed)
            }
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "rectangle.3.group",
            accessibilityDescription: "MenuFold"
        )
        button.image?.isTemplate = true
        button.toolTip = "MenuFold：打开折叠抽屉"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    private func connectModel() {
        model.onItemsChanged = { [weak self] items in
            guard let self else { return }
            guard !self.hasScheduledInitialReconcile, !items.isEmpty else { return }
            self.hasScheduledInitialReconcile = true
            self.sectionManager.scheduleReconcile(model: self.model, allowMovement: false)
        }
        model.onPreferencesChanged = { [weak self] in
            guard let self else { return }
            self.updateStatusItem()
        }
        model.onVisibilityChanged = { [weak self] in
            guard let self else { return }
            self.sectionManager.scheduleReconcile(model: self.model)
        }
        model.onNewItemsDiscovered = { [weak self] in
            guard let self else { return }
            self.sectionManager.scheduleReconcile(model: self.model)
        }
        model.onPanelRequested = { [weak self] in self?.togglePanel() }
        model.onSettingsRequested = { [weak self] in self?.openSettingsFlow() }
    }

    @objc private func statusItemClicked() {
        guard !sectionManager.isReconciling else { return }
        if let event = NSApp.currentEvent,
           event.modifierFlags.contains(.command)
            || event.cgEvent?.getIntegerValueField(.eventSourceUserData)
                == MenuFoldEventMarker.menuBarMove {
            return
        }
        if NSApp.currentEvent?.type == .rightMouseDown {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        if panelController.isVisible {
            panelController.close()
            return
        }

        let collapsed = model.collapsedItems
        guard !collapsed.isEmpty || model.preferences.showDashboard else {
            settingsController.show()
            return
        }

        panelController.show(relativeTo: statusItem.button)
    }

    private func activate(_ item: MenuBarItem) {
        guard model.hasAccessibilityAccess else {
            model.requestAccessibility()
            return
        }

        panelController.close()
        if !MenuBarActionService.press(item) {
            model.lastError = "无法打开 \(item.displayName)，该项目可能不支持辅助功能点击。"
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let title = model.statusTitle()
        button.title = title.isEmpty ? "" : " \(title)"
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    }

    private func openSettingsFlow() {
        panelController.close()
        settingsController.show()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "展开折叠栏", action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(withTitle: "重新扫描", action: #selector(rescan), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 MenuFold", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.minY - 4), in: button)
    }

    @objc private func openPanel() { togglePanel() }
    @objc private func rescan() { model.scanNow(animated: true) }
    @objc private func openSettings() { openSettingsFlow() }
    @objc private func quit() { NSApp.terminate(nil) }
}
