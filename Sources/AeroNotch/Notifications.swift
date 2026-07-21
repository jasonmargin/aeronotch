import Foundation

/// Notification names shared between the CLI (short-lived processes) and the running app.
enum Notifications {
    /// Posted by `AeroNotch ping-workspace-change`, which AeroSpace's
    /// `exec-on-workspace-change` hook invokes on every workspace switch.
    static let workspaceChanged = Notification.Name("com.aeronotch.workspace-changed")
}
