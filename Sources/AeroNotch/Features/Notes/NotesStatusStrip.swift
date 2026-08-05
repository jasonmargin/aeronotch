import SwiftUI

/// Persistent indicator in the notch's left cluster, between the workspaces
/// pill and the agents strip: a checklist glyph plus the count of open
/// to-dos (app + Obsidian). Hover/tap deep-links into the Notes drop-down.
struct NotesStatusStrip: View {
    @ObservedObject var store: NotesStore

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checklist")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            if store.openCount > 0 {
                Text("\(store.openCount)")
                    .font(.notch(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
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
        .help(helpText)
    }

    private var helpText: String {
        store.openCount == 0
            ? "Notes — no open to-dos"
            : "Notes — \(store.openCount) open to-do\(store.openCount == 1 ? "" : "s")"
    }
}
