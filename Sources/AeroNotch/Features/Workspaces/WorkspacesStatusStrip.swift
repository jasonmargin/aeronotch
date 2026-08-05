import SwiftUI

/// Persistent indicator in the notch's left cluster showing the *active
/// workspace on this screen* — name plus its app icons. Resting state for
/// the Workspaces feature: the notch itself stays closed until hovered
/// (no auto-expand on workspace switches).
struct WorkspacesStatusStrip: View {
    @ObservedObject var store: WorkspaceStore
    let config: AeroNotchConfig

    @Environment(\.aerospaceMonitorID) private var monitorID: Int?

    /// The workspace to highlight on *this* screen: the one visible on this
    /// screen's monitor, falling back to the globally focused one.
    private var activeWorkspace: String? {
        if let monitorID, let visible = store.snapshot.visibleByMonitor[monitorID] {
            return visible
        }
        return store.snapshot.focused
    }

    var body: some View {
        HStack(spacing: 5) {
            if !store.isAvailable {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.yellow)
            }
            Text(activeWorkspace ?? "—")
                .font(.notch(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            if config.showAppIcons, let active = activeWorkspace {
                let apps = store.snapshot.appsByWorkspace[active] ?? []
                if !apps.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(apps.prefix(config.maxAppIconsPerWorkspace), id: \.self) { app in
                            Image(nsImage: AppIconProvider.shared.icon(for: app))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 11, height: 11)
                        }
                        if apps.count > config.maxAppIconsPerWorkspace {
                            Text("+\(apps.count - config.maxAppIconsPerWorkspace)")
                                .font(.notch(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        }
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
        .help(helpText)
    }

    private var helpText: String {
        guard store.isAvailable else { return "AeroSpace not found" }
        guard let active = activeWorkspace else { return "Workspaces" }
        let apps = store.snapshot.appsByWorkspace[active] ?? []
        let title = "Workspace \(active)"
        return apps.isEmpty ? title : title + " — " + apps.map(\.name).joined(separator: ", ")
    }
}
