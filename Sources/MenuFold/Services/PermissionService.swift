import ApplicationServices
import CoreGraphics
import Foundation

enum PermissionService {
    static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

}
