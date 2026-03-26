import Foundation

final class AppPreferences {
    private enum Keys {
        static let hotKeyConfiguration = "PinShot.hotKeyConfiguration"
        static let launchAtLoginEnabled = "PinShot.launchAtLoginEnabled"
        static let showSetupGuideOnLaunch = "PinShot.showSetupGuideOnLaunch"
    }

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [
            Keys.launchAtLoginEnabled: true,
            Keys.showSetupGuideOnLaunch: true
        ])
    }

    var launchAtLoginEnabled: Bool {
        get { userDefaults.bool(forKey: Keys.launchAtLoginEnabled) }
        set { userDefaults.set(newValue, forKey: Keys.launchAtLoginEnabled) }
    }

    var showSetupGuideOnLaunch: Bool {
        get { userDefaults.bool(forKey: Keys.showSetupGuideOnLaunch) }
        set { userDefaults.set(newValue, forKey: Keys.showSetupGuideOnLaunch) }
    }

    func loadHotKeyConfiguration() -> HotKeyConfiguration {
        guard let data = userDefaults.data(forKey: Keys.hotKeyConfiguration),
              let configuration = try? decoder.decode(HotKeyConfiguration.self, from: data) else {
            return .default
        }

        return configuration
    }

    func saveHotKeyConfiguration(_ configuration: HotKeyConfiguration) {
        guard let data = try? encoder.encode(configuration) else { return }
        userDefaults.set(data, forKey: Keys.hotKeyConfiguration)
    }

    func markSetupGuideDismissed() {
        showSetupGuideOnLaunch = false
    }

    func resetSetupGuide() {
        showSetupGuideOnLaunch = true
    }
}
