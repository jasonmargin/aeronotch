import Foundation
import Combine

/// Runtime-writable settings. Wraps the on-disk `AeroNotchConfig`: mutations
/// update the live value (published to the app) and persist to
/// `~/.config/aeronotch/config.json` so they survive restarts.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var current: AeroNotchConfig

    /// Called after any mutation (AppDelegate rebuilds windows/view models).
    var onChange: ((AeroNotchConfig) -> Void)?

    var presentationMode: AeroNotchConfig.PresentationMode {
        current.presentationMode
    }

    init(config: AeroNotchConfig) {
        self.current = config
    }

    func setPresentationMode(_ mode: AeroNotchConfig.PresentationMode) {
        guard mode != current.presentationMode else { return }
        current.presentationMode = mode
        persist()
        onChange?(current)
    }

    func setAgentsShowClosedIndicator(_ value: Bool) {
        guard value != current.agentsShowClosedIndicator else { return }
        current.agentsShowClosedIndicator = value
        persist()
        onChange?(current)
    }

    func setAgentsEnabled(_ value: Bool) {
        guard value != current.agentsEnabled else { return }
        current.agentsEnabled = value
        persist()
        onChange?(current)
    }

    func setNotesEnabled(_ value: Bool) {
        guard value != current.notesEnabled else { return }
        current.notesEnabled = value
        persist()
        onChange?(current)
    }

    func setNotesShowClosedIndicator(_ value: Bool) {
        guard value != current.notesShowClosedIndicator else { return }
        current.notesShowClosedIndicator = value
        persist()
        onChange?(current)
    }

    func setCompletionWidgetEnabled(_ value: Bool) {
        guard value != current.completionWidgetEnabled else { return }
        current.completionWidgetEnabled = value
        persist()
        onChange?(current)
    }

    func setPeekOnWorkspaceSwitch(_ value: Bool) {
        guard value != current.peekOnWorkspaceSwitch else { return }
        current.peekOnWorkspaceSwitch = value
        persist()
        onChange?(current)
    }

    func setShowEmptyWorkspaces(_ value: Bool) {
        guard value != current.showEmptyWorkspaces else { return }
        current.showEmptyWorkspaces = value
        persist()
        onChange?(current)
    }

    func setShowAppIcons(_ value: Bool) {
        guard value != current.showAppIcons else { return }
        current.showAppIcons = value
        persist()
        onChange?(current)
    }

    func setHoverOpenDelaySeconds(_ value: TimeInterval) {
        guard value != current.hoverOpenDelaySeconds else { return }
        current.hoverOpenDelaySeconds = value
        persist()
        onChange?(current)
    }

    /// Persist which screen has a feature card pinned (nil display = none).
    /// Not a full settings change — no window rebuild needed.
    func setPinned(displayID: UInt32?, featureID: String?) {
        guard displayID != current.pinnedDisplayID || featureID != current.pinnedFeatureID else { return }
        current.pinnedDisplayID = displayID
        current.pinnedFeatureID = featureID
        persist()
    }

    private func persist() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: AeroNotchConfig.configDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(current) else { return }
        try? data.write(to: AeroNotchConfig.configFile, options: .atomic)
    }
}
