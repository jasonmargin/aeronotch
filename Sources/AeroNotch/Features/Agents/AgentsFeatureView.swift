import SwiftUI

/// Compact agent-session pills shown inside the expanded notch (Agents segment).
/// Deliberately minimal — glyph, status dot, folder — one click jumps to the
/// herdr pane running that session. Mirrors WorkspacesFeatureView's layout:
/// centered row, horizontal scroll fallback, live ideal-width reporting.
struct AgentsFeatureView: View {
    @ObservedObject var store: AgentSessionStore

    @EnvironmentObject private var vm: NotchViewModel

    var body: some View {
        Group {
            if !store.isAvailable {
                Label("herdr not found", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            } else if store.sessions.isEmpty {
                Text("No agent sessions")
                    .font(.caption)
                    .foregroundStyle(.gray)
            } else {
                ViewThatFits(in: .horizontal) {
                    pillsRow
                    ScrollView(.horizontal, showsIndicators: false) {
                        pillsRow
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: vm.presentationMode == .menuBarLeft ? .leading : .center
        )
        // Measure the row's *ideal* width (even when the visible copy scrolls)
        // and report it so the notch panel hugs the content.
        .background {
            pillsRow
                .fixedSize()
                .opacity(0)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { reportWidth(geo.size.width) }
                            .onChange(of: geo.size.width) { _, newWidth in reportWidth(newWidth) }
                    }
                )
        }
    }

    private func reportWidth(_ width: CGFloat) {
        vm.reportOpenContentWidth(width, for: store.id)
    }

    private var pillsRow: some View {
        HStack(spacing: 6) {
            ForEach(store.sessions) { session in
                SessionPillView(
                    session: session,
                    compact: vm.presentationMode == .menuBarLeft,
                    action: { store.focus(session) }
                )
            }
        }
    }
}

private struct SessionPillView: View {
    let session: AgentSession
    let compact: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                AgentGlyph(agent: session.agent, size: 11)
                AgentStatusDot(status: session.status)
                Text(session.shortCWD)
                    .font(.system(size: 12, weight: session.focused ? .bold : .medium, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, compact ? 3 : 5)
            .foregroundStyle(session.focused ? Color.white : Color.white.opacity(0.55))
            .background {
                Capsule().fill(
                    session.focused
                        ? Color.white.opacity(0.18)
                        : Color.white.opacity(isHovering ? 0.12 : 0.05)
                )
            }
            .overlay {
                Capsule().strokeBorder(
                    session.focused ? Color.white.opacity(0.35) : Color.clear,
                    lineWidth: 1
                )
            }
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .animation(.snappy(duration: 0.18), value: isHovering)
            .animation(.snappy(duration: 0.25), value: session.focused)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tooltip)
    }

    private var tooltip: String {
        "\(session.agent) · \(session.status.rawValue) · \(session.cwd)\nClick to focus this pane"
    }
}
