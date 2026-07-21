import Foundation

/// One AI coding-agent session as reported by herdr (`herdr agent list`).
/// herdr owns all detection (screen manifests + integrations); this is just
/// the snapshot it hands us — Claude Code, pi, and anything else it tracks.
struct AgentSession: Identifiable, Equatable, Sendable {
    /// herdr-reported lifecycle state (`idle|working|blocked|unknown`).
    enum Status: String, Sendable {
        case idle
        case working
        case blocked
        case unknown

        /// Higher = more attention-worthy (sorts first in the strip).
        var severity: Int {
            switch self {
            case .blocked: 3
            case .working: 2
            case .idle: 1
            case .unknown: 0
            }
        }
    }

    /// Agent label as reported by herdr ("claude", "pi", "codex", …).
    let agent: String
    let status: Status
    /// Working directory of the agent process.
    let cwd: String
    /// herdr pane identifier — also the focus target (`herdr agent focus <pane>`).
    let paneID: String
    /// Whether this pane currently has keyboard focus inside herdr.
    let focused: Bool

    var id: String { paneID }
}

/// Presentation helpers shared by the closed-notch strip and the panel.
enum AgentStyle {
    /// Compact per-agent glyph. Text-presentation dingbats (not emoji) so they
    /// tint with `foregroundStyle` and stay monochrome.
    static func glyph(for agent: String) -> String {
        switch agent.lowercased() {
        case "claude": "✻"
        case "pi": "π"
        case "codex": "❖"
        case "gemini": "✦"
        default: String(agent.prefix(1)).uppercased()
        }
    }
}

extension AgentSession {
    var glyph: String { AgentStyle.glyph(for: agent) }

    /// Last path component, home abbreviated to `~` ("/a/b/marginos" → "marginos").
    var shortCWD: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        var path = cwd
        if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
        return path.split(separator: "/").last.map(String.init) ?? path
    }
}
