import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var detailText: String {
        switch self {
        case .enabled:
            return "PinShot will open automatically when you sign in."
        case .disabled:
            return "PinShot will stay off until you launch it manually."
        case .requiresApproval:
            return "Allow PinShot in System Settings > General > Login Items to finish enabling auto-start."
        case .unavailable:
            return "Launch at login is applied by the packaged app in /Applications."
        }
    }
}

@MainActor
final class LaunchAtLoginService {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var isSupported: Bool {
        bundle.bundleURL.pathExtension == "app" && bundle.bundleIdentifier != nil
    }

    func currentState() -> LaunchAtLoginState {
        guard isSupported else { return .unavailable }

        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    func applyPreference(enabled: Bool) throws -> LaunchAtLoginState {
        guard isSupported else {
            return .unavailable
        }

        let service = SMAppService.mainApp
        let existingState = currentState()

        switch (enabled, existingState) {
        case (true, .enabled):
            return .enabled
        case (false, .disabled):
            return .disabled
        case (true, _):
            try service.register()
        case (false, _):
            try service.unregister()
        }

        return currentState()
    }
}
