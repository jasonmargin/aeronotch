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

    @State private var activeFeatureID: String?

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vm.presentationMode == .menuBarLeft ? .topTrailing : .top)
        .preferredColorScheme(.dark)
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

    private var menuBarModePanel: some View {
        HStack(spacing: 0) {
            if vm.state == .open {
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

            // The (fake) notch itself — always rendered; seamless over the hardware
            // notch, zero-gap to the band so hover never crosses a dead zone.
            // Exact width (no overhang) so nothing bleeds past the notch's right edge.
            Color.black
                .frame(width: vm.exactClosedNotchWidth, height: vm.closedNotchSize.height)
                .clipShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 14))
        }
        .padding(.trailing, 8)
        .animation(vm.state == .open ? openAnimation : closeAnimation, value: vm.state)
        .contentShape(Rectangle())
        .onHover { hovering in
            vm.handleHover(hovering)
        }
        .onTapGesture {
            vm.handleTap()
        }
    }

    // MARK: - Shared content

    @ViewBuilder
    private var openContent: some View {
        switch registry.features.count {
        case 0:
            Text("No features installed")
                .font(.caption)
                .foregroundStyle(.gray)
        case 1:
            registry.features[0].makeContentView()
        default:
            featureSwitcher
        }
    }

    /// Rendered once multiple features are registered — the extensibility payoff.
    private var featureSwitcher: some View {
        let active = registry.feature(withID: activeFeatureID ?? "") ?? registry.features[0]
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(registry.features, id: \.id) { feature in
                    Button {
                        activeFeatureID = feature.id
                    } label: {
                        Text(feature.displayName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background {
                                Capsule().fill(
                                    active.id == feature.id
                                        ? Color.white.opacity(0.2)
                                        : Color.clear
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
            active.makeContentView()
        }
    }
}
