import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let didPass = QualityCheckRunner.runIfRequested(arguments: CommandLine.arguments) {
            Darwin.exit(didPass ? 0 : 1)
        }

        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()

        if ProcessInfo.processInfo.environment["PINSHOT_CAPTURE_ON_LAUNCH"] == "1" {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                await AppModel.shared.captureAndPin()
            }
        }
    }
}
