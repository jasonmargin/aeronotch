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
            && !vm.isPinned
    }

    /// Persistent workspaces capsule (active workspace on this screen) —
    /// the outboard-most strip in the left cluster. The notch stays closed
    /// until hovered; this capsule is the at-a-glance state.
    private var showWorkspacesStrip: Bool { true }

    /// Measured width of the whole strip cluster — lets notch mode offset
    /// the (self-sizing) cluster left of the centered panel without
    /// disturbing the panel's centering.
    @State private var clusterWidth: CGFloat = 0

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
        ZStack(alignment: vm.presentationMode == .menuBarLeft ? .topTrailing : .top) {
            switch vm.presentationMode {
            case .notch:
                notchModePanel
            case .menuBarLeft:
                menuBarModePanel
            }

            // Notch mode: the strip cluster sits just left of the centered
            // panel, offset by its measured width — workspaces (outboard),
            // notes, agents. (menuBarLeft mode renders it as an HStack
            // sibling instead.)
            if vm.presentationMode == .notch {
                stripCluster
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: StripClusterWidthKey.self, value: geo.size.width)
                        }
                    )
                    .frame(height: vm.closedNotchSize.height)
                    .offset(x: clusterXOffset)
                    .animation(vm.state == .open ? openAnimation : closeAnimation, value: vm.state)
                    .animation(widthAnimation, value: vm.effectiveOpenWidth)
                    .animation(widthAnimation, value: clusterWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vm.presentationMode == .menuBarLeft ? .topTrailing : .top)
        .preferredColorScheme(.dark)
        .onPreferenceChange(StripClusterWidthKey.self) { clusterWidth = $0 }
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

    // MARK: - Menu-bar mode (band from the screen's leading edge to the notch)

    /// Notch-mode strip X: glued to the closed notch's left edge — stays put
    /// while the panel expands around/under it (lands on the panel's
    /// always-empty top strip).
    /// Cluster X: glued to the closed notch's left edge — stays put while
    /// the panel expands around/under it.
    private var clusterXOffset: CGFloat {
        -(vm.closedNotchSize.width / 2 + clusterWidth / 2 + 6)
    }

    /// True while the open panel is showing any downward detail — in
    /// menuBarLeft mode every feature (workspaces grid, agents, notes)
    /// drops out of the notch.
    private var showingNotchDropDetail: Bool {
        vm.state == .open
    }

    /// Cap on the Agents drop-down width. Also determines how far the window
    /// extends right of the notch, so that panel can stay centered on the notch.
    static let panelMaxWidth: CGFloat = 620

    /// Inner content height shared by the menu-bar workspace pill and the
    /// agents pill, so both capsules render at the same height.
    static let menuBarPillContentHeight: CGFloat = 16

    /// Span the window must cover right of screen-center: the wider of the
    /// fake notch and the panel cap.
    private var notchSpan: CGFloat {
        max(vm.exactClosedNotchWidth, NotchContentView.panelMaxWidth)
    }

    /// Trailing padding keeping the notch/detail-panel's center pinned at
    /// screen-center as it widens (window trailing edge = center + notchSpan/2 + 8).
    private var notchTrailingPadding: CGFloat {
        (notchSpan - detailPanelWidth) / 2 + 8
    }

    /// Trailing padding gluing the left cluster's (agent strip's) trailing edge
    /// to the *closed* notch's leading edge, with a small gap. The workspace
    /// pill sits outboard of the strip and grows leftward — never crossing this.
    private var clusterTrailingPadding: CGFloat {
        notchSpan / 2 + vm.exactClosedNotchWidth / 2 + 8 + 6
    }

    /// Detail drop-down width: the shared card width plus the panel's
    /// horizontal padding — identical for every FeaturePanel card; fake-notch
    /// width when closed so it never jumps on first open.
    private var detailPanelWidth: CGFloat {
        guard showingNotchDropDetail else { return vm.exactClosedNotchWidth }
        let content = vm.openContentWidths[vm.activeFeatureID] ?? FeaturePanelMetrics.contentWidth
        return min(content + 24, NotchContentView.panelMaxWidth)
    }

    /// Detail drop-down height: hugs the active feature's reported content
    /// height (Notes defaults to the tall notepad); closed-notch height when
    /// no detail is showing.
    private var detailPanelHeight: CGFloat {
        showingNotchDropDetail ? vm.effectiveOpenHeight : vm.closedNotchSize.height
    }

    private var menuBarModePanel: some View {
        ZStack {
            // The (fake) notch. Every feature drops downward out of it —
            // workspaces grid on plain hover (the default feature), agents /
            // notes via their strips. Always hoverable so the notch opens
            // exactly on hover (no auto-expand on workspace switches).
            ZStack(alignment: .top) {
                if showingNotchDropDetail {
                    VStack(spacing: 0) {
                        // Keep the notch strip empty; content lives below it.
                        // When pinned, the strip is excluded from the panel
                        // entirely (see pinnedPanelInset).
                        Spacer()
                            .frame(height: vm.closedNotchSize.height - pinnedPanelInset)
                        openContent
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .transition(
                        .scale(scale: 0.92, anchor: .top)
                            .combined(with: .opacity)
                    )
                }
            }
            .frame(width: detailPanelWidth, height: detailPanelHeight - pinnedPanelInset)
            .background(Color.black)
            .clipShape(
                NotchShape(
                    topCornerRadius: showingNotchDropDetail ? 19 : 6,
                    bottomCornerRadius: showingNotchDropDetail ? 24 : 14
                )
            )
            .offset(y: pinnedPanelInset)
            .shadow(color: showingNotchDropDetail ? .black.opacity(0.4) : .clear, radius: 10)
            .contentShape(Rectangle())
            .onHover { vm.handleHover($0) }
            .onTapGesture {
                vm.requestedFeatureID = nil
                vm.handleTap()
            }
            .padding(.trailing, notchTrailingPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Left cluster, glued to the notch's leading edge and growing
            // left: workspaces capsule (outboard), notes, agents.
            stripCluster
                .frame(height: vm.closedNotchSize.height)
                .padding(.trailing, clusterTrailingPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .animation(vm.state == .open ? openAnimation : closeAnimation, value: vm.state)
        .animation(widthAnimation, value: vm.requestedFeatureID)
        .animation(widthAnimation, value: vm.temporaryFeatureID)
        .animation(widthAnimation, value: vm.isPinned)
        .animation(widthAnimation, value: vm.openContentWidths)
        .animation(widthAnimation, value: vm.openContentHeights)
    }

    // MARK: - Shared content

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

/// Measured width of the whole left-edge strip cluster, reported up to
/// `NotchContentView` for notch-mode placement.
private struct StripClusterWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
