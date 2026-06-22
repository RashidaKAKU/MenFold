import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct MenuBarScanner {
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func scan() -> MenuBarScanResult {
        let runningApps = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )
        let windowResult = scanWindows(runningApps: runningApps)
        let accessibilityResult = scanAccessibility(runningApps: runningApps)

        var merged = accessibilityResult.candidates
        var entries = accessibilityResult.entries + windowResult.entries

        for candidate in windowResult.candidates {
            if let index = merged.firstIndex(where: { matches($0, candidate) }) {
                if merged[index].windowID == 0 {
                    merged[index].windowID = candidate.windowID
                }
                continue
            }
            merged.append(candidate)
        }

        merged.sort {
            if $0.ownerPID != $1.ownerPID { return $0.ownerPID < $1.ownerPID }
            return $0.bounds.minX < $1.bounds.minX
        }

        var occurrences: [String: Int] = [:]
        let items = merged.map { candidate in
            let base = "\(candidate.bundleIdentifier ?? candidate.ownerName)|\(candidate.windowName)"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return MenuBarItem(
                id: MenuBarItem.stableIdentifier(
                    bundleIdentifier: candidate.bundleIdentifier,
                    ownerName: candidate.ownerName,
                    windowName: candidate.windowName,
                    occurrence: occurrence
                ),
                windowID: candidate.windowID,
                ownerPID: candidate.ownerPID,
                ownerName: candidate.ownerName,
                bundleIdentifier: candidate.bundleIdentifier,
                windowName: candidate.windowName,
                bounds: candidate.bounds,
                displayID: display(containing: candidate.bounds),
                appIcon: candidate.appIcon
            )
        }
        .sorted { $0.bounds.minX < $1.bounds.minX }

        entries.sort {
            if $0.accepted != $1.accepted { return $0.accepted && !$1.accepted }
            if $0.ownerName != $1.ownerName { return $0.ownerName < $1.ownerName }
            return $0.bounds.minX < $1.bounds.minX
        }

        let failure: String?
        if !items.isEmpty {
            failure = nil
        } else if !PermissionService.hasAccessibilityAccess {
            failure = "辅助功能权限未生效"
        } else if windowResult.totalWindowCount <= 6 && accessibilityResult.itemCount == 0 {
            failure = "辅助功能没有返回菜单栏项目，权限可能尚未应用到当前进程"
        } else {
            failure = "扫描已完成，但两种扫描方式都没有找到菜单栏项目"
        }

        return MenuBarScanResult(
            items: items,
            totalWindowCount: windowResult.totalWindowCount,
            statusWindowCount: windowResult.candidates.count,
            accessibilityApplicationCount: accessibilityResult.applicationCount,
            accessibilityItemCount: accessibilityResult.itemCount,
            entries: entries,
            failureMessage: failure
        )
    }

    private func scanWindows(runningApps: [pid_t: NSRunningApplication]) -> WindowScan {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return WindowScan(candidates: [], entries: [], totalWindowCount: 0)
        }

        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        var candidates: [Candidate] = []
        var entries: [ScanDiagnosticEntry] = []

        for info in rawWindows {
            guard let windowNumber = info[kCGWindowNumber as String] as? NSNumber,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { continue }

            guard isInMenuBar(bounds) else { continue }

            let pid = pid_t(ownerPID.int32Value)
            let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? "未知项目"
            let windowName = (info[kCGWindowName as String] as? String) ?? ""
            let layerValue = layer.intValue
            let app = runningApps[pid]
            let rejection = windowRejectionReason(
                pid: pid,
                ownerName: ownerName,
                bundleIdentifier: app?.bundleIdentifier,
                windowName: windowName,
                bounds: bounds,
                layer: layerValue,
                statusLevel: statusLevel
            )

            if let rejection {
                entries.append(ScanDiagnosticEntry(
                    source: .window,
                    ownerName: ownerName,
                    itemName: windowName,
                    layer: layerValue,
                    bounds: bounds,
                    accepted: false,
                    reason: rejection
                ))
                continue
            }

            candidates.append(Candidate(
                windowID: CGWindowID(windowNumber.uint32Value),
                ownerPID: pid,
                ownerName: ownerName,
                bundleIdentifier: app?.bundleIdentifier,
                windowName: windowName,
                bounds: bounds,
                appIcon: app?.icon
            ))
            entries.append(ScanDiagnosticEntry(
                source: .window,
                ownerName: ownerName,
                itemName: windowName,
                layer: layerValue,
                bounds: bounds,
                accepted: true,
                reason: "窗口位置和层级符合菜单栏项目"
            ))
        }

        return WindowScan(
            candidates: candidates,
            entries: entries,
            totalWindowCount: rawWindows.count
        )
    }

    private func scanAccessibility(
        runningApps: [pid_t: NSRunningApplication]
    ) -> AccessibilityScan {
        guard PermissionService.hasAccessibilityAccess else {
            return AccessibilityScan(candidates: [], entries: [], applicationCount: 0, itemCount: 0)
        }

        var candidates: [Candidate] = []
        var entries: [ScanDiagnosticEntry] = []
        var applicationCount = 0

        for (pid, app) in runningApps where pid != ownPID && !app.isTerminated {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.12)
            var menuBarValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                application,
                kAXExtrasMenuBarAttribute as CFString,
                &menuBarValue
            )
            guard result == .success, let menuBarValue else { continue }
            applicationCount += 1

            let menuBar = menuBarValue as! AXUIElement
            for element in menuBarItems(in: menuBar) {
                guard let bounds = bounds(of: element),
                      bounds.width >= 4,
                      bounds.height >= 8,
                      isAtMenuBarHeight(bounds)
                else { continue }

                let name = firstNonemptyAttribute(
                    of: element,
                    keys: [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                )
                let ownerName = app.localizedName ?? app.bundleIdentifier ?? "未知项目"
                if MenuBarItem.isTransientBadge(
                    bundleIdentifier: app.bundleIdentifier,
                    ownerName: ownerName,
                    windowName: name
                ) {
                    entries.append(ScanDiagnosticEntry(
                        source: .accessibility,
                        ownerName: ownerName,
                        itemName: name,
                        layer: nil,
                        bounds: bounds,
                        accepted: false,
                        reason: "应用消息角标，不是独立菜单栏项目"
                    ))
                    continue
                }
                candidates.append(Candidate(
                    windowID: 0,
                    ownerPID: pid,
                    ownerName: ownerName,
                    bundleIdentifier: app.bundleIdentifier,
                    windowName: name,
                    bounds: bounds,
                    appIcon: app.icon
                ))
                entries.append(ScanDiagnosticEntry(
                    source: .accessibility,
                    ownerName: ownerName,
                    itemName: name,
                    layer: nil,
                    bounds: bounds,
                    accepted: true,
                    reason: "辅助功能 ExtrasMenuBar 返回项目"
                ))
            }
        }

        return AccessibilityScan(
            candidates: candidates,
            entries: entries,
            applicationCount: applicationCount,
            itemCount: candidates.count
        )
    }

    private func menuBarItems(in root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]

        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            if stringAttribute(of: element, key: kAXRoleAttribute) == (kAXMenuBarItemRole as String) {
                result.append(element)
                continue
            }
            guard depth < 3 else { continue }

            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
                  let children = childrenValue as? [AXUIElement]
            else { continue }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return result
    }

    private func bounds(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
              AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &sizeValue
              ) == .success,
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

    private func firstNonemptyAttribute(of element: AXUIElement, keys: [String]) -> String {
        for key in keys {
            let value = stringAttribute(of: element, key: key)
            if !value.isEmpty { return value }
        }
        return ""
    }

    private func stringAttribute(of element: AXUIElement, key: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else {
            return ""
        }
        return value as? String ?? ""
    }

    private func windowRejectionReason(
        pid: pid_t,
        ownerName: String,
        bundleIdentifier: String?,
        windowName: String,
        bounds: CGRect,
        layer: Int,
        statusLevel: Int
    ) -> String? {
        if pid == ownPID { return "MenuFold 自身项目" }
        if ownerName == "Window Server" || ownerName == "Dock" || ownerName == "程序坞" {
            return "系统菜单栏背景或程序坞窗口"
        }
        if MenuBarItem.isTransientBadge(
            bundleIdentifier: bundleIdentifier,
            ownerName: ownerName,
            windowName: windowName
        ) {
            return "应用消息角标，不是独立菜单栏项目"
        }
        if bounds.width < 8 || bounds.width > 320 || bounds.height < 12 || bounds.height > 64 {
            return "尺寸不像独立菜单栏项目"
        }
        if !isStatusLayer(layer, statusLevel: statusLevel) {
            return "窗口层级 \(layer) 不属于菜单栏"
        }
        return nil
    }

    private func isStatusLayer(_ layer: Int, statusLevel: Int) -> Bool {
        layer == 0 || (statusLevel - 2 ... statusLevel + 2).contains(layer)
    }

    private func isInMenuBar(_ bounds: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            let displayBounds = CGDisplayBounds(screen.displayID)
            let menuHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
            return bounds.intersects(CGRect(
                x: displayBounds.minX,
                y: displayBounds.minY,
                width: displayBounds.width,
                height: menuHeight + 6
            ))
        }
    }

    private func isAtMenuBarHeight(_ bounds: CGRect) -> Bool {
        let maximumMenuHeight = NSScreen.screens.map {
            max(24, $0.frame.maxY - $0.visibleFrame.maxY)
        }.max() ?? 40
        return bounds.minY <= CGFloat(maximumMenuHeight + 6)
            && bounds.maxY >= 0
            && bounds.height <= 64
    }

    private func display(containing bounds: CGRect) -> CGDirectDisplayID {
        NSScreen.screens.first { CGDisplayBounds($0.displayID).intersects(bounds) }?.displayID
            ?? CGMainDisplayID()
    }

    private func matches(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        guard lhs.ownerPID == rhs.ownerPID else { return false }
        let centerDistance = hypot(lhs.bounds.midX - rhs.bounds.midX, lhs.bounds.midY - rhs.bounds.midY)
        return centerDistance < 10 || lhs.bounds.intersection(rhs.bounds).width >= min(lhs.bounds.width, rhs.bounds.width) * 0.6
    }
}

enum ScanDiagnosticSource: String {
    case accessibility = "辅助功能"
    case window = "窗口层"
}

struct ScanDiagnosticEntry: Identifiable {
    let id = UUID()
    let source: ScanDiagnosticSource
    let ownerName: String
    let itemName: String
    let layer: Int?
    let bounds: CGRect
    let accepted: Bool
    let reason: String

    var title: String { itemName.isEmpty ? ownerName : "\(ownerName) · \(itemName)" }

    var technicalDetail: String {
        let frame = "x:\(Int(bounds.minX)) y:\(Int(bounds.minY)) \(Int(bounds.width))×\(Int(bounds.height))"
        if let layer { return "\(source.rawValue) · 层级 \(layer) · \(frame)" }
        return "\(source.rawValue) · \(frame)"
    }
}

struct MenuBarScanResult {
    let items: [MenuBarItem]
    let totalWindowCount: Int
    let statusWindowCount: Int
    let accessibilityApplicationCount: Int
    let accessibilityItemCount: Int
    let entries: [ScanDiagnosticEntry]
    let failureMessage: String?
}

private struct Candidate {
    var windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let bundleIdentifier: String?
    let windowName: String
    let bounds: CGRect
    let appIcon: NSImage?
}

private struct WindowScan {
    let candidates: [Candidate]
    let entries: [ScanDiagnosticEntry]
    let totalWindowCount: Int
}

private struct AccessibilityScan {
    let candidates: [Candidate]
    let entries: [ScanDiagnosticEntry]
    let applicationCount: Int
    let itemCount: Int
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()
    }
}
