import SwiftUI

/// Root view inside the (fixed-size, transparent) notch window.
/// The window never resizes — the notch panel morphs within it, which is what
/// makes the motion fluid. Empty regions of this view hit-test to `nil`, so
/// everything outside the notch shape stays click-through to the desktop.
///
/// Spring timings mirror TheBoringNotch's (open: bouncy, close: critically damped).
struct NotchContentView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var registry: NotchFeatureRegistry
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var agentStore: AgentSessionStore
    @EnvironmentObject var notesStore: NotesStore

    /// Persistent herdr agent-status strip pinned to the notch's left edge.
    /// Always visible while the feature is enabled and sessions exist —
    /// workspace peeks/panels don't hide it.
    private var showAgentsStrip: Bool {
        vm.config.agentsEnabled
            && vm.config.agentsShowClosedIndicator
            && !agentStore.sessions.isEmpty
    }

    /// Persistent notes strip in the left cluster, between the workspaces
    /// capsule and the agents strip. Always visible while the feature is
    /// enabled (it's the entry point into the drop-down, so it shows even
    /// with zero open to-dos).
    private var showNotesStrip: Bool {
        vm.config.notesEnabled
            && vm.config.notesShowClosedIndicator
            && vm.pinnedFeatureID != notesStore.id
    }

    /// Persistent workspaces capsule (active workspace on this screen) —
    /// the outboard-most strip in the left cluster. The notch stays closed
    /// until hovered; this capsule is the at-a-glance state.
    private var showWorkspacesStrip: Bool { true }

    @ViewBuilder
    private var workspacesStrip: some View {
        WorkspacesStatusStrip(store: workspaceStore, config: vm.config)
            .contentShape(Rectangle())
            .onTapGesture {
                if vm.isPinned { vm.temporaryFeatureID = workspaceStore.id }
                vm.requestedFeatureID = nil
                vm.handleTap()
            }
            .onHover { hovering in
                if hovering {
                    // Workspaces is the default feature — clear any stale deep
                    // link. Pinned: show the grid over the notes panel instead.
                    if vm.isPinned {
                        vm.temporaryFeatureID = workspaceStore.id
                    } else {
                        vm.requestedFeatureID = nil
                    }
                } else {
                    vm.temporaryFeatureID = nil
                }
                vm.handleHover(hovering)
            }
            .transition(.opacity)
    }

    @ViewBuilder
    private var agentsStrip: some View {
        AgentsStatusStrip(store: agentStore)
            .contentShape(Rectangle())
            .onTapGesture {
                // Pinned: the tap can't steal the panel from Notes — show the
                // Agents list as a transient overlay instead.
                if vm.isPinned { vm.temporaryFeatureID = agentStore.id }
                vm.requestedFeatureID = agentStore.id
                vm.handleTap()
            }
            .onHover { hovering in
                if hovering {
                    // Pinned: hover shows Agents *over* the notes panel
                    // (same height, reverts on exit) instead of deep-linking.
                    if vm.isPinned {
                        vm.temporaryFeatureID = agentStore.id
                    } else {
                        vm.requestedFeatureID = agentStore.id
                    }
                } else {
                    vm.temporaryFeatureID = nil
                    if vm.state == .closed {
                        // Never opened — don't let the deep link go stale.
                        vm.requestedFeatureID = nil
                    }
                }
                vm.handleHover(hovering)
            }
            .transition(.opacity)
    }

    @ViewBuilder
    private var notesStrip: some View {
        NotesStatusStrip(store: notesStore)
            .contentShape(Rectangle())
            .onTapGesture {
                vm.requestedFeatureID = notesStore.id
                vm.handleTap()
            }
            .onHover { hovering in
                if hovering {
                    vm.requestedFeatureID = notesStore.id
                } else if vm.state == .closed {
                    // Never opened — don't let the deep link go stale.
                    vm.requestedFeatureID = nil
                }
                vm.handleHover(hovering)
            }
            .transition(.opacity)
    }

    private var openAnimation: Animation {
        .spring(response: 0.16, dampingFraction: 0.85, blendDuration: 0)
    }
    private var closeAnimation: Animation {
        .spring(response: 0.15, dampingFraction: 0.95, blendDuration: 0)
    }

    private var topRadius: CGFloat { vm.state == .open ? 19 : 6 }
    private var bottomRadius: CGFloat { vm.state == .open ? 24 : 14 }
    private var currentSize: CGSize {
        vm.state == .open
            ? CGSize(width: vm.effectiveOpenWidth, height: vm.effectiveOpenHeight)
            : vm.closedNotchSize
    }
    private var widthAnimation: Animation {
        .spring(response: 0.2, dampingFraction: 0.85, blendDuration: 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            notchModePanel

            // The strip cluster — workspaces (outboard), notes, agents —
            // anchored by its trailing edge to the physical notch's leading
            // edge. Anchored from the window edge (no width measurement), so
            // strips appearing/disappearing never shift it under the notch.
            HStack {
                Spacer(minLength: 0)
                stripCluster
                    .frame(height: vm.closedNotchSize.height)
            }
            .padding(.trailing, clusterTrailingPadding)
            .animation(vm.state == .open ? openAnimation : closeAnimation, value: vm.state)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onChange(of: vm.state) { _, newState in
            // One-shot deep link: applies to a single open, then resets.
            if newState == .closed { vm.requestedFeatureID = nil }
        }
    }

    /// The left-edge cluster, ordered outboard → inboard: workspaces, notes,
    /// agents. Visibility rules live on each strip; the HStack just hugs
    /// whatever is present.
    @ViewBuilder
    private var stripCluster: some View {
        HStack(spacing: 6) {
            if showWorkspacesStrip { workspacesStrip }
            if showNotesStrip { notesStrip }
            if showAgentsStrip { agentsStrip }
        }
    }

    // MARK: - Notch mode (panel expands downward out of the notch)

    /// Pinned panels don't draw over the menu bar: the reserved
    /// hardware-notch strip stays transparent and the whole panel hangs
    /// below it. Content keeps the exact same position either way — only
    /// the black strip over the menu bar is gone.
    private var pinnedPanelInset: CGFloat {
        vm.isPinned ? vm.closedNotchSize.height : 0
    }

    private var notchModePanel: some View {
        ZStack {
            if vm.state == .open {
                // The top strip stays empty so it can slide *behind* the physical
                // notch (which has no pixels to draw over); all content lives
                // below the hardware cutout. When pinned, the strip is excluded
                // from the panel entirely (see pinnedPanelInset).
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: vm.closedNotchSize.height - pinnedPanelInset)
                    openContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(
                    .scale(scale: 0.85, anchor: .top)
                        .combined(with: .opacity)
                )
            }
        }
        .frame(width: currentSize.width, height: currentSize.height - pinnedPanelInset)
        .background(Color.black)
        .clipShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        .offset(y: pinnedPanelInset)
        .shadow(color: vm.state == .open ? .black.opacity(0.55) : .clear, radius: 10)
        .animation(vm.state == .open ? openAnimation : closeAnimation, value: vm.state)
        .animation(widthAnimation, value: vm.effectiveOpenWidth)
        .animation(widthAnimation, value: vm.effectiveOpenHeight)
        .animation(widthAnimation, value: vm.temporaryFeatureID)
        .animation(widthAnimation, value: vm.isPinned)
        .contentShape(Rectangle())
        .onHover { hovering in
            vm.handleHover(hovering)
        }
        .onTapGesture {
            vm.handleTap()
        }
    }

    // MARK: - Shared content

    /// Trailing padding gluing the strip cluster's trailing edge to the
    /// *physical* notch's leading edge with a 6pt gap: window trailing =
    /// center + maxOpenWidth/2; target = center - exactNotchWidth/2 - 6.
    private var clusterTrailingPadding: CGFloat {
        vm.config.maxOpenWidth / 2 + vm.exactClosedNotchWidth / 2 + 6
    }

    /// Inner content height shared by the strip capsules, so they all render
    /// at the same height.
    static let menuBarPillContentHeight: CGFloat = 16

    /// One feature at a time — no tabs. Content is chosen by context:
    /// workspace peeks show workspaces; opening via a strip deep-links to
    /// that feature; a pinned screen always shows Notes.
    @ViewBuilder
    private var openContent: some View {
        let active = registry.feature(withID: vm.activeFeatureID) ?? registry.features.first
        if let active {
            active.makeContentView()
        } else {
            Text("Nothing to show")
                .font(.notch(size: 11))
                .foregroundStyle(.gray)
        }
    }
}
