import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--lifecycle-check") {
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                print("Lifecycle checks exceeded 30 seconds")
                Darwin.exit(1)
            }
            Task { @MainActor in
                Darwin.exit(await AsyncLifecycleChecks.run() ? 0 : 1)
            }
            return
        }
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
