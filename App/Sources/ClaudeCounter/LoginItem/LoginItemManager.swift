import Foundation
import ServiceManagement

/// Wraps SMAppService.mainApp for Login Items.
/// macOS 13+ — System Settings -> General -> Login Items shows the app.
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enables/disables auto-launch on login. Throws on permission denial.
    static func setEnabled(_ enable: Bool) throws {
        let service = SMAppService.mainApp
        if enable {
            if service.status != .enabled {
                try service.register()
            }
        } else {
            if service.status == .enabled {
                try service.unregister()
            }
        }
    }
}
