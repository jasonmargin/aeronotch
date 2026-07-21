import SwiftUI

/// A pluggable notch content feature.
///
/// This is the extensibility seam: v1 ships the AeroSpace workspaces feature,
/// and any future feature (media, battery, calendar, …) conforms to this
/// protocol and calls `NotchFeatureRegistry.register(_:)`. Features render
/// one at a time — the open notch shows a single row chosen by context
/// (peek vs. deep link), never tabs.
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
        guard !features.contains(where: { $0.id == feature.id }) else { return }
        features.append(feature)
    }

    func unregister(withID id: String) {
        features.removeAll { $0.id == id }
    }

    func feature(withID id: String) -> (any NotchFeature)? {
        features.first { $0.id == id }
    }
}
