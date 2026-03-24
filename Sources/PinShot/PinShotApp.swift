import SwiftUI

@main
struct PinShotApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var appModel = AppModel.shared

    var body: some Scene {
        MenuBarExtra("PinShot", systemImage: "pin.fill") {
            ContentView(appModel: appModel)
        }
        .menuBarExtraStyle(.window)
    }
}
