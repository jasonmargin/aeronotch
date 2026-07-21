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

    /// Notch-mode strip X: glued to the closed notch's left edge; rides into
    /// the open panel's top-left "forehead" (the always-empty notch strip)
    /// so it stays visible and never leaves the window.
    private var stripXOffset: CGFloat {
        if vm.state == .open {
            return -(vm.effectiveOpenWidth / 2) + stripWidth / 2 + 12
        }
        return -(vm.closedNotchSize.width / 2 + stripWidth / 2 + 6)
    }

    /// True while the open panel is showing the Agents detail (vs. workspaces).
    private var showingAgentsDetail: Bool {
        vm.state == .open && vm.requestedFeatureID == agentStore.id
    }

    /// Agents popover width: hugs the measured content, capped.
    private var agentsDetailWidth: CGFloat {
        min((vm.openContentWidth ?? 220) + 24, 620)
    }

    private var menuBarModePanel: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 0) {
                if vm.state == .open, !showingAgentsDetail {
                    // Workspaces: band from the screen's leading edge to the notch.
                    openContent
                        .padding(.leading, 12)
                        .padding(.trailing, 10)
                        .frame(width: vm.menuBarBandWidth, height: vm.closedNotchSize.height, alignment: .leading)
                        .background(Color.black)
                        .shadow(color: .black.opacity(0.35), radius: 8)
                        .transition(
                            .move(edge: .leading)
                                .combined(with: .opacity)
                        )
                }
                if showAgentsStrip {
                    // Always-on indicator glued to the notch's left edge —
                    // stays put whether the panel is open or closed.
                    agentsStrip
                        .padding(.trailing, 6)
                }

                // The (fake) notch itself — always rendered; seamless over the hardware
                // notch, zero-gap to the band so hover never crosses a dead zone.
                // Exact width (no overhang) so nothing bleeds past the notch's right edge.
                Color.black
                    .frame(width: vm.exactClosedNotchWidth, height: vm.closedNotchSize.height)
                    .clipShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 14))
            }
            .padding(.trailing, 8)

            if showingAgentsDetail {
                // Agents detail: popover hanging from the notch itself, right
                // edge flush with the notch's right edge (never the left band).
                openContent
                    .padding(.horizontal, 12)
                    .frame(width: agentsDetailWidth, height: 40)
                    .background(Color.black)
                    .clipShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 14))
                    .shadow(color: .black.opacity(0.35), radius: 8)
                    .padding(.top, 4)
                    .padding(.trailing, 8)
                    .transition(
                        .scale(scale: 0.9, anchor: .topTrailing)
                            .combined(with: .opacity)
                    )
            }
        }
        .animation(vm.state == .open ? openAnimation : closeAnimation, value: vm.state)
        .animation(widthAnimation, value: vm.requestedFeatureID)
        .contentShape(Rectangle())
        .onHover { hovering in
            vm.handleHover(hovering)
        }
        .onTapGesture {
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
