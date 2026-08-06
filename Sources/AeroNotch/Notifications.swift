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
    /// Posted by `AeroNotch ping-workspaces`: external request to open the
    /// Workspaces grid (useful for hotkeys and testing).
    static let workspacesRequested = Notification.Name("com.aeronotch.workspaces-requested")
    /// Posted by `AeroNotch ping-new-todo`: focus the add-a-to-do field in
    /// the Notes drop-down (opens it first when closed).
    static let newTodoRequested = Notification.Name("com.aeronotch.new-todo-requested")
}
