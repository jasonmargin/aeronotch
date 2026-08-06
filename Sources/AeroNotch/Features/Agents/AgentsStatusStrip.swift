import SwiftUI

/// A single session status dot, strictly monochrome:
/// working = filled white (pulsing), blocked = thick ring (pulsing),
/// idle = thin dim ring, unknown = faint ring.
struct AgentStatusDot: View {
    let status: AgentSession.Status
    /// Pulse phase driven by the parent's repeating animation.
    var pulsing: Bool = false

    private var animated: Bool { status == .working || status == .blocked }

    var body: some View {
        Group {
            switch status {
            case .working:
                Circle().fill(Color.white)
            case .blocked:
                Circle().strokeBorder(Color.white, lineWidth: 2)
            case .idle:
                Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
            case .unknown:
                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            }
        }
        .frame(width: 7, height: 7)
        .opacity(animated ? (pulsing ? 1 : 0.35) : 1)
    }
}

/// Persistent indicator pinned to the *left edge of the closed notch*:
/// one glyph per agent kind (✻ claude, π pi, …) followed by a status dot
/// per session — herdr's `idle|working|blocked` states at a glance.
///
/// Rendered as an overlay outside the notch panel's leading edge, so it lives
/// in the menu bar next to the notch without disturbing the notch itself.
struct AgentsStatusStrip: View {
    @ObservedObject var store: AgentSessionStore

    @State private var pulsing = false

    /// Cap on dots per agent group; overflow renders as "+N".
    private let maxDotsPerGroup = 6

    private struct AgentGroup {
        let agent: String
        let sessions: [AgentSession]

        var worstSeverity: Int { sessions.map(\.status.severity).max() ?? 0 }
    }

    private var groups: [AgentGroup] {
        Dictionary(grouping: store.sessions, by: \.agent)
            .map { AgentGroup(agent: $0.key, sessions: $0.value) }
            .sorted { lhs, rhs in
                lhs.worstSeverity != rhs.worstSeverity
                    ? lhs.worstSeverity > rhs.worstSeverity
                    : lhs.agent < rhs.agent
            }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(groups, id: \.agent) { group in
                HStack(spacing: 4) {
                    AgentGlyph(agent: group.agent, size: 11)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .layoutPriority(1)
                    ForEach(group.sessions.prefix(maxDotsPerGroup)) { session in
                        AgentStatusDot(status: session.status, pulsing: pulsing)
                            .layoutPriority(1)
                    }
                    if group.sessions.count > maxDotsPerGroup {
                        Text("+\(group.sessions.count - maxDotsPerGroup)")
                            .font(.notch(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        // Match the workspace pill's capsule height (NotchContentView.menuBarPillContentHeight).
        .frame(height: NotchContentView.menuBarPillContentHeight)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            ZStack {
                Capsule().fill(Color.black)
                Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .help(helpText)
    }

    private var helpText: String {
        let counts = Dictionary(grouping: store.sessions, by: \.status)
            .mapValues(\.count)
        let parts = [
            counts[.blocked].map { "\($0) blocked" },
            counts[.working].map { "\($0) working" },
            counts[.idle].map { "\($0) idle" },
        ].compactMap { $0 }
        return "Agent sessions — " + (parts.isEmpty ? "none" : parts.joined(separator: ", "))
    }
}
