import SwiftUI

/// Dimensions shared by every notch drop-down card.
enum FeaturePanelMetrics {
    /// Card width shared by all three drop-downs.
    static let contentWidth: CGFloat = 400
    /// Header row + section spacing + bottom padding. List features add
    /// this to their measured content height when reporting ideal height.
    static let chromeHeight: CGFloat = 42
}

/// Shared canvas for every notch drop-down (Workspaces, Agents, Notes):
/// one width, one padding, one header treatment — all three cards read as
/// the same component. The feature supplies title/subtitle, optional
/// trailing header buttons, and body content; the panel owns the chrome.
///
/// Card width is a constant (FeaturePanelMetrics.contentWidth) — the notch
/// panel sizes itself from it directly, so every card gets identical
/// geometry with no measurement round-trip. Ideal *height* stays
/// feature-driven: list features compute it from their row counts and
/// report `rows + FeaturePanelMetrics.chromeHeight`; Notes keeps the fixed
/// notepad height (see NotchViewModel.effectiveOpenHeight).
struct FeaturePanel<Content: View>: View {
    let featureID: String
    let title: String
    let subtitle: String?
    let trailing: AnyView
    @ViewBuilder var content: Content

    @EnvironmentObject private var vm: NotchViewModel

    init(
        featureID: String,
        title: String,
        subtitle: String? = nil,
        trailing: AnyView = AnyView(EmptyView()),
        @ViewBuilder content: () -> Content
    ) {
        self.featureID = featureID
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.notch(size: 12, weight: .semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.notch(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                trailing
                Button(action: { vm.togglePinned(featureID) }) {
                    Image(systemName: vm.pinnedFeatureID == featureID ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(vm.pinnedFeatureID == featureID ? 0 : 45))
                }
                .buttonStyle(HeaderButtonStyle(active: vm.pinnedFeatureID == featureID))
                .help(vm.pinnedFeatureID == featureID ? "Unpin — resume auto-hiding" : "Pin open on this screen")
            }
            .foregroundStyle(.white.opacity(0.85))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(width: FeaturePanelMetrics.contentWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Shared style for small header buttons (pin, refresh) on drop-down cards.
struct HeaderButtonStyle: ButtonStyle {
    var active: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(active ? 0.95 : (configuration.isPressed ? 0.7 : 0.45)))
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(configuration.isPressed || active ? 0.12 : 0))
            }
    }
}
