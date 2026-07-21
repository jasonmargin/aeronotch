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
