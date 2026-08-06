import Foundation

/// User-tunable settings, loaded once at launch from `~/.config/aeronotch/config.json`.
/// Every key is optional in the file; these defaults apply when missing.
struct AeroNotchConfig: Codable, Sendable {
    /// How the expanded popover presents itself.
    enum PresentationMode: String, Codable, Sendable {
        /// Panel expanding downward out of the notch.
        case notch
        /// Slim menu-bar-height strip attached to the left of the notch.
        case menuBarLeft
    }

    /// Presentation mode for the *workspaces* popover.
    /// (The Agents detail always opens at the notch itself.)
    var presentationMode: PresentationMode = .notch
    /// Fallback polling interval for workspace state (the exec hook is the primary signal).
    var pollIntervalSeconds: TimeInterval = 2.0
    /// Expand the notch briefly on every workspace switch. Off by default —
    /// the notch opens on hover; the active workspace shows in the strip capsule.
    var peekOnWorkspaceSwitch: Bool = false
    /// How long the notch stays expanded after a workspace switch.
    var peekDurationSeconds: TimeInterval = 1.5
    /// Delay before hovering the notch expands it (filters casual fly-bys).
    var hoverOpenDelaySeconds: TimeInterval = 0.12
    /// Show every configured workspace, or only non-empty ones plus the focused one.
    var showEmptyWorkspaces: Bool = false
    /// Show app icons inside workspace pills.
    var showAppIcons: Bool = true
    /// Cap on app icons per pill (overflow renders as "+N").
    var maxAppIconsPerWorkspace: Int = 3
    /// Cap on the expanded notch width — the actual width adapts to the content
    /// (measured live) between a minimum and this cap.
    var maxOpenWidth: CGFloat = 720
    /// Expanded notch height (total, including the reserved hardware-notch strip).
    var openHeight: CGFloat = 74
    /// Workspaces to never show in the notch.
    var hiddenWorkspaces: [String] = []
    /// Explicit path to the aerospace binary (auto-detected when nil).
    var aerospacePath: String? = nil

    /// Polling cadence for `herdr agent list`.
    var agentsPollIntervalSeconds: TimeInterval = 3.0
    /// Master switch for the herdr agent-session feature (panel segment + closed-notch indicator).
    var agentsEnabled: Bool = true
    /// Show the persistent agent-status strip pinned to the notch's left edge.
    var agentsShowClosedIndicator: Bool = true
    /// Explicit path to the herdr binary (auto-detected when nil).
    var herdrPath: String? = nil

    /// Master switch for the Notes notepad (drop-down + closed-notch indicator).
    var notesEnabled: Bool = true
    /// Show the persistent notes strip pinned to the notch's right edge.
    var notesShowClosedIndicator: Bool = true
    /// Explicit Obsidian vault paths to scan for `- [ ]` tasks. When nil,
    /// vaults are auto-discovered (margindept-kb + Obsidian's own registry).
    var notesVaultPaths: [String]? = nil
    /// Expanded height of the Notes drop-down.
    var notesMaxHeight: CGFloat = 460
    /// Rescan cadence for Obsidian vaults.
    var notesScanIntervalSeconds: TimeInterval = 60
    /// Show the desktop completion-heatmap widget.
    var completionWidgetEnabled: Bool = false
    /// Screen (CoreGraphics display id) where a feature card is pinned open.
    var pinnedDisplayID: UInt32? = nil
    /// Feature pinned on that screen ("workspaces" | "agents" | "notes").
    var pinnedFeatureID: String? = nil

    enum CodingKeys: String, CodingKey {
        case presentationMode
        case pollIntervalSeconds, peekOnWorkspaceSwitch, peekDurationSeconds, hoverOpenDelaySeconds
        case showEmptyWorkspaces, showAppIcons, maxAppIconsPerWorkspace
        case maxOpenWidth, openHeight, hiddenWorkspaces, aerospacePath
        case agentsEnabled, agentsPollIntervalSeconds, agentsShowClosedIndicator, herdrPath
        case notesEnabled, notesShowClosedIndicator, notesVaultPaths
        case notesMaxHeight, notesScanIntervalSeconds, completionWidgetEnabled
        case pinnedDisplayID, pinnedFeatureID
    }

    /// `openWidth` was the fixed expanded width in <=0.1; now treated as the cap.
    /// `notesPinnedDisplayID` pinned Notes only; now feature-generalized.
    private enum LegacyCodingKeys: String, CodingKey {
        case openWidth
        case notesPinnedDisplayID
    }

    init() {}

    init(from decoder: Decoder) throws {
        let defaults = AeroNotchConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        presentationMode = try c.decodeIfPresent(PresentationMode.self, forKey: .presentationMode) ?? defaults.presentationMode
        pollIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .pollIntervalSeconds) ?? defaults.pollIntervalSeconds
        peekOnWorkspaceSwitch = try c.decodeIfPresent(Bool.self, forKey: .peekOnWorkspaceSwitch) ?? defaults.peekOnWorkspaceSwitch
        peekDurationSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .peekDurationSeconds) ?? defaults.peekDurationSeconds
        hoverOpenDelaySeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .hoverOpenDelaySeconds) ?? defaults.hoverOpenDelaySeconds
        showEmptyWorkspaces = try c.decodeIfPresent(Bool.self, forKey: .showEmptyWorkspaces) ?? defaults.showEmptyWorkspaces
        showAppIcons = try c.decodeIfPresent(Bool.self, forKey: .showAppIcons) ?? defaults.showAppIcons
        maxAppIconsPerWorkspace = try c.decodeIfPresent(Int.self, forKey: .maxAppIconsPerWorkspace) ?? defaults.maxAppIconsPerWorkspace
        maxOpenWidth = try c.decodeIfPresent(CGFloat.self, forKey: .maxOpenWidth)
            ?? legacy.decodeIfPresent(CGFloat.self, forKey: .openWidth)
            ?? defaults.maxOpenWidth
        openHeight = try c.decodeIfPresent(CGFloat.self, forKey: .openHeight) ?? defaults.openHeight
        hiddenWorkspaces = try c.decodeIfPresent([String].self, forKey: .hiddenWorkspaces) ?? defaults.hiddenWorkspaces
        aerospacePath = try c.decodeIfPresent(String.self, forKey: .aerospacePath)
        agentsEnabled = try c.decodeIfPresent(Bool.self, forKey: .agentsEnabled) ?? defaults.agentsEnabled
        agentsPollIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .agentsPollIntervalSeconds) ?? defaults.agentsPollIntervalSeconds
        agentsShowClosedIndicator = try c.decodeIfPresent(Bool.self, forKey: .agentsShowClosedIndicator) ?? defaults.agentsShowClosedIndicator
        herdrPath = try c.decodeIfPresent(String.self, forKey: .herdrPath)
        notesEnabled = try c.decodeIfPresent(Bool.self, forKey: .notesEnabled) ?? defaults.notesEnabled
        notesShowClosedIndicator = try c.decodeIfPresent(Bool.self, forKey: .notesShowClosedIndicator) ?? defaults.notesShowClosedIndicator
        notesVaultPaths = try c.decodeIfPresent([String].self, forKey: .notesVaultPaths)
        notesMaxHeight = try c.decodeIfPresent(CGFloat.self, forKey: .notesMaxHeight) ?? defaults.notesMaxHeight
        notesScanIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .notesScanIntervalSeconds) ?? defaults.notesScanIntervalSeconds
        completionWidgetEnabled = try c.decodeIfPresent(Bool.self, forKey: .completionWidgetEnabled) ?? defaults.completionWidgetEnabled
        let legacyPinned = try legacy.decodeIfPresent(UInt32.self, forKey: .notesPinnedDisplayID)
        pinnedDisplayID = try c.decodeIfPresent(UInt32.self, forKey: .pinnedDisplayID) ?? legacyPinned
        pinnedFeatureID = try c.decodeIfPresent(String.self, forKey: .pinnedFeatureID) ?? (legacyPinned != nil ? "notes" : nil)
    }

    static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/aeronotch")
    }

    static var configFile: URL {
        configDirectory.appending(path: "config.json")
    }

    static func load() -> AeroNotchConfig {
        guard let data = try? Data(contentsOf: configFile) else { return .init() }
        return (try? JSONDecoder().decode(AeroNotchConfig.self, from: data)) ?? .init()
    }
}
