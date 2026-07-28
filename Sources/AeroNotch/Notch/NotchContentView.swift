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
    @EnvironmentObject var agentStore: AgentSessionStore

    /// Persistent herdr agent-status strip pinned to the notch's left edge.
    /// Always visible while the feature is enabled and sessions exist —
    /// workspace peeks/panels don't hide it.
    private var showAgentsStrip: Bool {
        vm.config.agentsEnabled
            && vm.config.agentsShowClosedIndicator
            && !agentStore.sessions.isEmpty
    }

    /// Measured strip width — lets notch mode offset the (self-sizing) strip
    /// left of the centered panel without disturbing the panel's centering.
    @State private var stripWidth: CGFloat = 0

    @ViewBuilder
    private var agentsStrip: some View {
        AgentsStatusStrip(store: agentStore)
            .contentShape(Rectangle())
            .onTapGesture {
                vm.requestedFeatureID = agentStore.id
                vm.handleTap()
            }
            .onHover { hovering in
                if hovering {
                    vm.requestedFeatureID = agentStore.id
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
            ? CGSize(width: vm.effectiveOpenWidth, height: vm.maxOpenSize.height)
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

            // Notch mode: strip sits left of the centered panel, offset by its
            // measured width. (menuBarLeft mode renders it as an HStack sibling.)
            if vm.presentationMode == .notch, showAgentsStrip {
                agentsStrip
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: AgentsStripWidthKey.self, value: geo.size.width)
                        }
                    )
                    .frame(height: vm.closedNotchSize.height)
                    .offset(x: stripXOffset)
                    .animation(vm.state == .open ? openAnimation : closeAnimation, value: vm.state)
                    .animation(widthAnimation, value: vm.effectiveOpenWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vm.presentationMode == .menuBarLeft ? .topTrailing : .top)
        .preferredColorScheme(.dark)
        .onPreferenceChange(AgentsStripWidthKey.self) { stripWidth = $0 }
        .onChange(of: vm.state) { _, newState in
            // One-shot deep link: applies to a single open, then resets.
            if newState == .closed { vm.requestedFeatureID = nil }
        }
    }

    // MARK: - Notch mode (panel expands downward out of the notch)

    private var notchModePanel: some View {
        ZStack {
            if vm.state == .open {
                // The top strip stays empty so it can slide *behind* the physical
                // notch (which has no pixels to draw over); all content lives
                // below the hardware cutout.
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: vm.closedNotchSize.height)
                    openContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(
                    .scale(scale: 0.85, anchor: .top)
                        .combined(with: .opacity)
                )
            }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .background(Color.black)
        .clipShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        .shadow(color: vm.state == .open ? .black.opacity(0.55) : .clear, radius: 10)
        .animation(vm.state == .open ? openAnimation : closeAnimation, value: vm.state)
        .animation(widthAnimation, value: vm.effectiveOpenWidth)
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
    private var stripXOffset: CGFloat {
        -(vm.closedNotchSize.width / 2 + stripWidth / 2 + 6)
    }

    /// True while the open panel is showing the Agents detail (vs. workspaces).
    /// Agents keep the downward notch drop; workspaces use the left-morphing pill.
    private var showingAgentsDetail: Bool {
        vm.state == .open && vm.requestedFeatureID == agentStore.id
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

    /// Trailing padding keeping the notch/Agents-panel's center pinned at
    /// screen-center as it widens (window trailing edge = center + notchSpan/2 + 8).
    private var notchTrailingPadding: CGFloat {
        (notchSpan - agentsPanelWidth) / 2 + 8
    }

    /// Trailing padding gluing the left cluster's (agent strip's) trailing edge
    /// to the *closed* notch's leading edge, with a small gap. The workspace
    /// pill sits outboard of the strip and grows leftward — never crossing this.
    private var clusterTrailingPadding: CGFloat {
        notchSpan / 2 + vm.exactClosedNotchWidth / 2 + 8 + 6
    }

    /// Agents drop-down width: hugs the measured content, capped; fake-notch
    /// width when closed so it never jumps on first open.
    private var agentsPanelWidth: CGFloat {
        showingAgentsDetail
            ? min((vm.openContentWidths[agentStore.id] ?? 220) + 24, NotchContentView.panelMaxWidth)
            : vm.exactClosedNotchWidth
    }

    /// Agents drop-down height: grows downward only while hosting the detail.
    private var agentsPanelHeight: CGFloat {
        showingAgentsDetail ? vm.closedNotchSize.height + 44 : vm.closedNotchSize.height
    }

    private var menuBarModePanel: some View {
        ZStack {
            // The (fake) notch. Stays a bare closed shape for workspaces (which
            // live in the pill); only the Agents deep link drops it downward.
            // Non-interactive while closed so the menu bar under it stays usable
            // and workspace hover is owned solely by the pill.
            ZStack(alignment: .top) {
                if showingAgentsDetail {
                    VStack(spacing: 0) {
                        // Keep the notch strip empty; content lives below it.
                        Spacer()
                            .frame(height: vm.closedNotchSize.height)
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
            .frame(width: agentsPanelWidth, height: agentsPanelHeight)
            .background(Color.black)
            .clipShape(
                NotchShape(
                    topCornerRadius: showingAgentsDetail ? 19 : 6,
                    bottomCornerRadius: showingAgentsDetail ? 24 : 14
                )
            )
            .shadow(color: showingAgentsDetail ? .black.opacity(0.4) : .clear, radius: 10)
            .contentShape(Rectangle())
            .allowsHitTesting(showingAgentsDetail)
            .onHover { vm.handleHover($0) }
            .padding(.trailing, notchTrailingPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Left cluster, glued to the notch's leading edge and growing left:
            // the workspace pill (outboard) then the agent strip (inboard).
            HStack(spacing: 6) {
                workspacePill
                if showAgentsStrip { agentsStrip }
            }
            .frame(height: vm.closedNotchSize.height)
            .padding(.trailing, clusterTrailingPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .animation(vm.state == .open ? openAnimation : closeAnimation, value: vm.state)
        .animation(widthAnimation, value: vm.requestedFeatureID)
        .animation(widthAnimation, value: vm.openContentWidths)
    }

    /// The always-visible workspace pill. Resting: focused-workspace label.
    /// Hover: morphs left into the full workspace row (hover is the *only*
    /// trigger in this mode). Self-sizing, so the capsule hugs its content.
    private var workspacePill: some View {
        Group {
            if let workspaces = registry.feature(withID: vm.defaultFeatureID) {
                workspaces.makeContentView()
            }
        }
        // Shared menu-bar pill height (kept in sync with AgentsStatusStrip) so
        // the workspace pill and agents pill render at the same capsule height.
        .frame(height: NotchContentView.menuBarPillContentHeight)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            ZStack {
                Capsule().fill(Color.black)
                Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            }
        }
        .contentShape(Capsule())
        .onHover { hovering in
            // Deep-link to workspaces so a prior Agents open never lingers.
            if hovering {
                vm.requestedFeatureID = nil
            } else if vm.state == .closed {
                vm.requestedFeatureID = nil
            }
            vm.handleHover(hovering)
        }
        .onTapGesture {
            vm.requestedFeatureID = nil
            vm.handleTap()
        }
    }

    // MARK: - Shared content

    /// One row, one feature — no tabs. Content is chosen by context:
    /// workspace peeks show workspaces; opening via the agent strip deep-links
    /// to Agents; otherwise the first registered feature shows.
    @ViewBuilder
    private var openContent: some View {
        let active = registry.feature(withID: vm.requestedFeatureID ?? "") ?? registry.features.first
        if let active {
            active.makeContentView()
        } else {
            Text("Nothing to show")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }
}

/// Measured width of the agents strip, reported from the strip up to
/// `NotchContentView` for notch-mode placement.
private struct AgentsStripWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
