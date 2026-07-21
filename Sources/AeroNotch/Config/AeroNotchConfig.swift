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

    /// Presentation mode for the expanded popover.
    var presentationMode: PresentationMode = .notch
    /// Fallback polling interval for workspace state (the exec hook is the primary signal).
    var pollIntervalSeconds: TimeInterval = 2.0
    /// How long the notch stays expanded after a workspace switch.
    var peekDurationSeconds: TimeInterval = 1.5
    /// Delay before hovering the notch expands it (near-zero: just filters zero-time fly-bys).
    var hoverOpenDelaySeconds: TimeInterval = 0.03
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

    enum CodingKeys: String, CodingKey {
        case presentationMode
        case pollIntervalSeconds, peekDurationSeconds, hoverOpenDelaySeconds
        case showEmptyWorkspaces, showAppIcons, maxAppIconsPerWorkspace
        case maxOpenWidth, openHeight, hiddenWorkspaces, aerospacePath
    }

    /// `openWidth` was the fixed expanded width in <=0.1; now treated as the cap.
    private enum LegacyCodingKeys: String, CodingKey {
        case openWidth
    }

    init() {}

    init(from decoder: Decoder) throws {
        let defaults = AeroNotchConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        presentationMode = try c.decodeIfPresent(PresentationMode.self, forKey: .presentationMode) ?? defaults.presentationMode
        pollIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .pollIntervalSeconds) ?? defaults.pollIntervalSeconds
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
