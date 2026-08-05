import Foundation

/// Notification names shared between the CLI (short-lived processes) and the running app.
enum Notifications {
    /// Posted by `AeroNotch ping-workspace-change`, which AeroSpace's
    /// `exec-on-workspace-change` hook invokes on every workspace switch.
    static let workspaceChanged = Notification.Name("com.aeronotch.workspace-changed")
    /// Posted by `AeroNotch ping-agents`: external request to open the Agents
    /// detail popover (useful for hotkeys and testing).
    static let agentsRequested = Notification.Name("com.aeronotch.agents-requested")
    /// Posted by `AeroNotch ping-notes`: external request to open the Notes
    /// drop-down (useful for hotkeys and testing).
    static let notesRequested = Notification.Name("com.aeronotch.notes-requested")
}
