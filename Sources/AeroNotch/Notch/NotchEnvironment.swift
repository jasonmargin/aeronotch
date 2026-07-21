import SwiftUI

private struct AerospaceMonitorIDKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The AeroSpace monitor-id this notch window renders for.
    /// Injected per window; nil when the mapping is unavailable.
    var aerospaceMonitorID: Int? {
        get { self[AerospaceMonitorIDKey.self] }
        set { self[AerospaceMonitorIDKey.self] = newValue }
    }
}
