import SwiftUI

/// A pluggable notch content feature.
///
/// This is the extensibility seam: v1 ships the AeroSpace workspaces feature,
/// and any future feature (media, battery, calendar, …) conforms to this
/// protocol and calls `NotchFeatureRegistry.register(_:)`. With more than one
/// feature registered, the notch automatically renders a segmented switcher.
@MainActor
protocol NotchFeature: AnyObject {
    var id: String { get }
    var displayName: String { get }
    func makeContentView() -> AnyView
}

@MainActor
final class NotchFeatureRegistry: ObservableObject {
    @Published private(set) var features: [any NotchFeature] = []

    func register(_ feature: any NotchFeature) {
        features.append(feature)
    }

    func feature(withID id: String) -> (any NotchFeature)? {
        features.first { $0.id == id }
    }
}
