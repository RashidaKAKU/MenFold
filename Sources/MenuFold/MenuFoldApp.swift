import AppKit
import SwiftUI

@main
struct MenuFoldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel()
        let controller = StatusBarController(model: model)
        self.model = model
        statusController = controller
        controller.start()

        if CommandLine.arguments.contains("--scan-diagnostic") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                print(model.scanReportText())
                NSApp.terminate(nil)
            }
            return
        }

        if CommandLine.arguments.contains("--smoke-test") {
            controller.runSmokeTest { succeeded in
                print(succeeded ? "MenuFold interaction smoke-test passed" : "MenuFold interaction smoke-test failed")
                NSApp.terminate(nil)
            }
            return
        }

        if !UserDefaults.standard.bool(forKey: "MenuFold.hasLaunched") {
            UserDefaults.standard.set(true, forKey: "MenuFold.hasLaunched")
            model.onSettingsRequested?()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusController?.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.refreshAfterActivation()
    }
}
