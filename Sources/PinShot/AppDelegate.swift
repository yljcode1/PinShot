import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-check") {
            let didPass = SelfCheckRunner.run()
            Darwin.exit(didPass ? 0 : 1)
        }

        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }
}
