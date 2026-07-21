import SwiftUI

/// Row of workspace pills shown inside the expanded notch.
/// Centers the row when everything fits; falls back to horizontal scrolling
/// when there are more workspaces than the notch is wide.
struct WorkspacesFeatureView: View {
    @ObservedObject var store: WorkspaceStore
    let config: AeroNotchConfig

    @Environment(\.aerospaceMonitorID) private var monitorID: Int?
    @EnvironmentObject private var vm: NotchViewModel

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
                    .font(.caption)
                    .foregroundStyle(.yellow)
            } else if workspaces.isEmpty {
                Text("No workspaces")
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
            ForEach(workspaces, id: \.self) { workspace in
                WorkspacePillView(
                    name: workspace,
                    isFocused: workspace == focusedWorkspace,
                    apps: store.snapshot.appsByWorkspace[workspace] ?? [],
                    showIcons: config.showAppIcons,
                    maxIcons: config.maxAppIconsPerWorkspace,
                    compact: vm.presentationMode == .menuBarLeft,
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
    let compact: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(name)
                    .font(.system(size: 12, weight: isFocused ? .bold : .medium, design: .rounded))

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
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, compact ? 3 : 5)
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
