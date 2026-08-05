import SwiftUI

/// Workspace grid shown inside the expanded notch — same drop-down layout
/// language as Agents/Notes: pills wrapping at a fixed number per row,
/// hugging the measured content size. Clicking a pill switches workspace.
struct WorkspacesFeatureView: View {
    @ObservedObject var store: WorkspaceStore
    let config: AeroNotchConfig

    @Environment(\.aerospaceMonitorID) private var monitorID: Int?
    @EnvironmentObject private var vm: NotchViewModel

    /// Max pills per row; extra workspaces wrap onto the next row (never one
    /// over-long row).
    static let maxPerRow = 5

    /// The workspace to highlight on *this* screen: the one visible on this
    /// screen's monitor, falling back to the globally focused one.
    private var focusedWorkspace: String? {
        if let monitorID, let visible = store.snapshot.visibleByMonitor[monitorID] {
            return visible
        }
        return store.snapshot.focused
    }

    private var workspaces: [String] {
        store.visibleWorkspaces(
            showEmpty: config.showEmptyWorkspaces,
            hidden: config.hiddenWorkspaces,
            alsoVisible: focusedWorkspace
        )
    }

    var body: some View {
        Group {
            if !store.isAvailable {
                Label("AeroSpace not found", systemImage: "exclamationmark.triangle")
                    .font(.notch(size: 11))
                    .foregroundStyle(.yellow)
            } else if workspaces.isEmpty {
                Text("No workspaces")
                    .font(.notch(size: 11))
                    .foregroundStyle(.gray)
            } else {
                gridPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Grid panel

    private var gridPanel: some View {
        FeaturePanel(featureID: store.id, title: "Workspaces", subtitle: focusedWorkspace) {
            ScrollView(showsIndicators: false) {
                grid
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: reportIdealHeight)
        .onChange(of: workspaces) { _, _ in reportIdealHeight() }
    }

    /// Pills are fixed-height (single line + padding), so the ideal height is
    /// computed directly from the row count — no hidden measurement pass,
    /// no post-open resize lag.
    private func reportIdealHeight() {
        let rowHeight: CGFloat = 27
        let rows = CGFloat((workspaces.count + Self.maxPerRow - 1) / Self.maxPerRow)
        vm.reportOpenContentHeight(
            rows * rowHeight + max(rows - 1, 0) * 6 + FeaturePanelMetrics.chromeHeight,
            for: store.id
        )
    }

    /// Flexible 5-column grid: cells stretch to the card's full width and
    /// pills center within their cells, so any row count spreads edge to edge.
    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: Self.maxPerRow),
            spacing: 6
        ) {
            ForEach(workspaces, id: \.self) { workspace in
                WorkspacePillView(
                    name: workspace,
                    isFocused: workspace == focusedWorkspace,
                    apps: store.snapshot.appsByWorkspace[workspace] ?? [],
                    showIcons: config.showAppIcons,
                    maxIcons: config.maxAppIconsPerWorkspace,
                    action: { store.switchToWorkspace(workspace, onMonitor: monitorID) }
                )
            }
        }
    }
}

private struct WorkspacePillView: View {
    let name: String
    let isFocused: Bool
    let apps: [AeroAppInfo]
    let showIcons: Bool
    let maxIcons: Int
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(name)
                    .font(.notch(size: 12, weight: isFocused ? .bold : .medium))

                if showIcons && !apps.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(apps.prefix(maxIcons), id: \.self) { app in
                            Image(nsImage: AppIconProvider.shared.icon(for: app))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 13, height: 13)
                        }
                        if apps.count > maxIcons {
                            Text("+\(apps.count - maxIcons)")
                                .font(.notch(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(isFocused ? Color.white : Color.white.opacity(0.55))
            .background {
                Capsule().fill(
                    isFocused
                        ? Color.white.opacity(0.18)
                        : Color.white.opacity(isHovering ? 0.12 : 0.05)
                )
            }
            .overlay {
                Capsule().strokeBorder(
                    isFocused ? Color.white.opacity(0.35) : Color.clear,
                    lineWidth: 1
                )
            }
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .animation(.snappy(duration: 0.18), value: isHovering)
            .animation(.snappy(duration: 0.25), value: isFocused)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tooltip)
    }

    private var tooltip: String {
        let title = "Workspace \(name)"
        guard !apps.isEmpty else { return title }
        return title + " — " + apps.map(\.name).joined(separator: ", ")
    }
}
