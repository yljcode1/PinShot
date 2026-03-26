import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let didPass = QualityCheckRunner.runIfRequested(arguments: CommandLine.arguments) {
            Darwin.exit(didPass ? 0 : 1)
        }

        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }
}
