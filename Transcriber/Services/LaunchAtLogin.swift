import ServiceManagement

@Observable
final class LaunchAtLogin {
    var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[LaunchAtLogin] \(error)")
            }
        }
    }
}
