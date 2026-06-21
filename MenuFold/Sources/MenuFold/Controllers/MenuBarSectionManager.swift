import AppKit

@MainActor
final class MenuBarSectionManager {
    private enum Constants {
        static let autosaveName = "MenuFold.HiddenDivider"
        static let preferredPositionKey = "NSStatusItem Preferred Position \(autosaveName)"
        static let organizingLength: CGFloat = 8
        static let hiddenLength: CGFloat = 700
    }

    private let divider: NSStatusItem
    private var dividerWidthConstraint: NSLayoutConstraint?
    private var spacerWidthConstraint: NSLayoutConstraint?
    private var reconcileTask: Task<Void, Never>?
    private(set) var isReconciling = false

    init() {
        if UserDefaults.standard.object(forKey: Constants.preferredPositionKey) == nil {
            UserDefaults.standard.set(CGFloat(1), forKey: Constants.preferredPositionKey)
        }
        divider = NSStatusBar.system.statusItem(withLength: 0)
        divider.autosaveName = Constants.autosaveName
        divider.button?.image = nil
        divider.button?.cell?.isEnabled = false
        divider.button?.toolTip = "MenuFold 隐藏分隔符"
        if let button = divider.button {
            dividerWidthConstraint = button.window?.contentView?
                .constraintsAffectingLayout(for: .horizontal)
                .first { $0.secondItem === button.superview }
            dividerWidthConstraint?.isActive = true
            spacerWidthConstraint = button.widthAnchor.constraint(
                equalToConstant: Constants.organizingLength
            )
            spacerWidthConstraint?.priority = .required
            spacerWidthConstraint?.isActive = true
        }
        divider.length = Constants.organizingLength
        spacerWidthConstraint?.constant = Constants.organizingLength
    }

    func scheduleReconcile(model: AppModel, allowMovement: Bool = true) {
        guard !isReconciling else { return }
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor [weak self, weak model] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self, let model else { return }
            await self.reconcile(model: model, allowMovement: allowMovement)
        }
    }

    func stop() {
        reconcileTask?.cancel()
        divider.length = Constants.organizingLength
        spacerWidthConstraint?.constant = Constants.organizingLength
        dividerWidthConstraint?.isActive = true
        let cachedPosition = UserDefaults.standard.object(forKey: Constants.preferredPositionKey)
        NSStatusBar.system.removeStatusItem(divider)
        UserDefaults.standard.set(cachedPosition, forKey: Constants.preferredPositionKey)
    }

    private func reconcile(model: AppModel, allowMovement: Bool) async {
        guard !isReconciling, model.hasAccessibilityAccess else { return }
        isReconciling = true
        defer { isReconciling = false }

        divider.length = Constants.organizingLength
        divider.button?.image = nil
        try? await Task.sleep(for: .milliseconds(240))
        model.scanNow(animated: false)

        guard var dividerFrame = quartzDividerFrame() else {
            model.lastError = "无法取得菜单栏分隔符位置"
            return
        }
        let initialDividerX = Int(dividerFrame.minX)
        var movedVisible = 0
        var movedObscured = 0

        let visibleIDs: [String] = allowMovement
            ? Array(model.items.filter {
                model.visibility(for: $0) == .visible && $0.isMovable
            }.map(\.id).reversed())
            : []
        for id in visibleIDs {
            for _ in 0 ..< 3 {
                model.scanNow(animated: false)
                dividerFrame = quartzDividerFrame() ?? dividerFrame
                guard let item = model.items.first(where: { $0.id == id }) else { break }
                if item.bounds.minX >= dividerFrame.maxX - 1 { break }
                guard await MenuBarItemMover.move(item, to: .right, of: dividerFrame) else {
                    continue
                }
                model.scanNow(animated: false)
                dividerFrame = quartzDividerFrame() ?? dividerFrame
                if let current = model.items.first(where: { $0.id == id }),
                   current.bounds.minX >= dividerFrame.maxX - 1 {
                    movedVisible += 1
                    break
                }
            }
        }

        let obscuredIDs: [String] = allowMovement
            ? model.items.filter {
                model.visibility(for: $0) != .visible && $0.isMovable
            }.map(\.id)
            : []
        for id in obscuredIDs {
            for _ in 0 ..< 3 {
                model.scanNow(animated: false)
                dividerFrame = quartzDividerFrame() ?? dividerFrame
                guard let item = model.items.first(where: { $0.id == id }) else { break }
                if item.bounds.maxX <= dividerFrame.minX + 1 { break }
                guard await MenuBarItemMover.move(item, to: .left, of: dividerFrame) else {
                    continue
                }
                model.scanNow(animated: false)
                dividerFrame = quartzDividerFrame() ?? dividerFrame
                if let current = model.items.first(where: { $0.id == id }),
                   current.bounds.maxX <= dividerFrame.minX + 1 {
                    movedObscured += 1
                    break
                }
            }
        }

        spacerWidthConstraint?.constant = Constants.hiddenLength
        divider.length = Constants.hiddenLength
        dividerWidthConstraint?.isActive = true
        divider.button?.image = nil
        divider.button?.isHighlighted = false
        try? await Task.sleep(for: .milliseconds(220))
        model.scanNow(animated: false)
        let finalFrame = quartzDividerFrame()
        model.updateLayoutDiagnostic(
            "分隔符 x:\(initialDividerX) → x:\(Int(finalFrame?.minX ?? 0))，宽 \(Int(finalFrame?.width ?? 0))，约束 \(dividerWidthConstraint == nil ? "缺失" : "有效")，显示区移动 \(movedVisible) 个，隐藏区移动 \(movedObscured) 个"
        )
    }

    private func quartzDividerFrame() -> CGRect? {
        if let accessibilityFrame = MenuBarActionService.ownItemFrame(
            named: "MenuFold 隐藏分隔符"
        ) {
            return accessibilityFrame
        }
        guard let window = divider.button?.window,
              let screen = window.screen
        else { return nil }
        let appKitFrame = window.frame
        let displayBounds = CGDisplayBounds(screen.displayID)
        return CGRect(
            x: displayBounds.minX + appKitFrame.minX - screen.frame.minX,
            y: displayBounds.minY + screen.frame.maxY - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }
}
