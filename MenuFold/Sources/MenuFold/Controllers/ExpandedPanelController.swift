import AppKit
import SwiftUI

@MainActor
final class ExpandedPanelController {
    private let model: AppModel
    private let panel: NSPanel
    private var pendingClose: DispatchWorkItem?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var notificationTokens: [NSObjectProtocol] = []
    var onActivate: ((MenuBarItem) -> Void)?

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: model.preferences.panelWidth, height: 260),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true

        panel.contentView = NSHostingView(
            rootView: ExpandedPanelView(model: model) { [weak self] item in
                self?.onActivate?(item)
            }
        )
        installFocusMonitoring()
    }

    var isVisible: Bool { panel.isVisible }

    func show(relativeTo statusButton: NSStatusBarButton?) {
        cancelPendingClose()
        guard !panel.isVisible else {
            close()
            return
        }

        let screen = statusButton?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let fittingSize = panel.contentView?.fittingSize ?? CGSize(width: model.preferences.panelWidth, height: 260)
        let width = min(max(340, model.preferences.panelWidth), screen.visibleFrame.width - 24)
        let height = min(max(150, fittingSize.height), screen.visibleFrame.height - 40)
        let menuBarHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)

        let anchorX = statusButton?.window?.frame.midX ?? screen.visibleFrame.maxX - width / 2
        let x = min(max(screen.visibleFrame.minX + 12, anchorX - width / 2), screen.visibleFrame.maxX - width - 12)
        let y = screen.frame.maxY - menuBarHeight - height - 8
        panel.setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        cancelPendingClose()
        panel.orderOut(nil)
    }

    func stop() {
        cancelPendingClose()
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor) }
        localEventMonitor = nil
        globalEventMonitor = nil
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        notificationTokens.removeAll()
    }

    func simulateFocusLossForTesting() {
        scheduleAutoClose()
    }

    private func installFocusMonitoring() {
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            if Self.isInternalMoveEvent(event) { return event }
            Task { @MainActor in self?.handleLocalMouseEvent() }
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            guard !Self.isInternalMoveEvent(event) else { return }
            Task { @MainActor in self?.scheduleAutoClose() }
        }

        let resignToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleAutoClose() }
        }
        notificationTokens.append(resignToken)

        let activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            Task { @MainActor in self?.scheduleAutoClose() }
        }
        notificationTokens.append(activationToken)
    }

    private func handleLocalMouseEvent() {
        guard panel.isVisible else { return }
        if panel.frame.contains(NSEvent.mouseLocation) {
            cancelPendingClose()
        } else {
            scheduleAutoClose()
        }
    }

    private func scheduleAutoClose() {
        guard panel.isVisible,
              model.preferences.panelAutoCloseEnabled,
              pendingClose == nil
        else { return }
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.close() }
        }
        pendingClose = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + model.preferences.panelAutoCloseDelay,
            execute: workItem
        )
    }

    private func cancelPendingClose() {
        pendingClose?.cancel()
        pendingClose = nil
    }

    private nonisolated static func isInternalMoveEvent(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            || event.cgEvent?.getIntegerValueField(.eventSourceUserData)
                == MenuFoldEventMarker.menuBarMove
    }
}
