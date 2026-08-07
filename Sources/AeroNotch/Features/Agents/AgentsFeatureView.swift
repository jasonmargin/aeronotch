import SwiftUI

/// Agent-session list shown inside the expanded notch (Agents feature).
/// Same layout language as the Notes drop-down: a header row, then one row
/// per session — glyph, pulsing status dot, folder, agent/status caption.
/// Click a row to jump to the herdr pane running that session.
///
/// The panel hugs the content: ideal width and height are measured on a
/// hidden fixed-size copy and reported to the view model, which clamps the
/// height between the single-row default and the notepad cap.
struct AgentsFeatureView: View {
    @ObservedObject var store: AgentSessionStore

    @EnvironmentObject private var vm: NotchViewModel

    private var sortedSessions: [AgentSession] {
        store.sortedSessions
    }

    var body: some View {
        Group {
            if !store.isAvailable {
                Label("herdr not found", systemImage: "exclamationmark.triangle")
                    .font(.notch(size: 11))
                    .foregroundStyle(.yellow)
            } else if store.sessions.isEmpty {
                Text("No agent sessions")
                    .font(.notch(size: 11))
                    .foregroundStyle(.gray)
            } else {
                listPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - List panel

    private var listPanel: some View {
        FeaturePanel(featureID: store.id, title: "Agents", subtitle: summary) {
            ScrollView(showsIndicators: false) {
                rows
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: reportIdealHeight)
        .onChange(of: store.sessions) { _, _ in reportIdealHeight() }
    }

    /// Rows are fixed-height (two text lines + padding), so the ideal height
    /// is computed directly from the session count — no hidden measurement
    /// pass, no post-open resize lag. Fits ~11 sessions before scrolling.
    private func reportIdealHeight() {
        let rowHeight: CGFloat = 36
        let count = CGFloat(store.sessions.count)
        vm.reportOpenContentHeight(
            count * rowHeight + max(count - 1, 0) * 2 + FeaturePanelMetrics.chromeHeight,
            for: store.id
        )
    }

    private var summary: String {
        let counts = Dictionary(grouping: store.sessions, by: \.status).mapValues(\.count)
        return [
            counts[.working].map { "\($0) working" },
            counts[.blocked].map { "\($0) blocked" },
            counts[.idle].map { "\($0) idle" },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                SessionRow(
                    session: session,
                    isSelected: vm.vimNavActive && index == store.selectionIndex,
                    action: { store.focus(session) }
                )
            }
        }
    }
}

// MARK: - Row

private struct SessionRow: View {
    let session: AgentSession
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 8) {
            AgentGlyph(agent: session.agent, size: 12)
                .foregroundStyle(.white.opacity(session.focused ? 0.9 : 0.6))
                .frame(width: 14)
            AgentStatusDot(status: session.status, pulsing: pulsing)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.shortCWD)
                    .font(.notch(size: 12, weight: session.focused ? .bold : .medium))
                    .foregroundStyle(.white.opacity(session.focused ? 0.9 : 0.85))
                    .lineLimit(1)
                Text("\(session.agent) · \(session.status.rawValue) · \(session.cwd)")
                    .font(.notch(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(isSelected ? 0.1 : (isHovering ? 0.08 : 0)))
        }
        .overlay {
            if isSelected || session.focused {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.45 : 0.2), lineWidth: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: action)
        .help("\(session.agent) · \(session.status.rawValue) · \(session.cwd)\nClick to focus this pane")
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}
