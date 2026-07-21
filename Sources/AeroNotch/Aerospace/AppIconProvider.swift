import AppKit

/// Resolves app icons for workspace pills. Prefers the running app's own icon
/// (works even for apps outside /Applications), falls back to bundle lookup,
/// then to a generic symbol. Results are cached for the app's lifetime.
@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private var cache: [String: NSImage] = [:]
    private lazy var fallbackIcon: NSImage =
        NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()

    /// Warm the cache off the render path (called after each workspace refresh).
    func preload(apps: [AeroAppInfo]) {
        for app in apps where cache[cacheKey(for: app)] == nil {
            cache[cacheKey(for: app)] = resolve(app) ?? fallbackIcon
        }
    }

    func icon(for app: AeroAppInfo) -> NSImage {
        let key = cacheKey(for: app)
        if let cached = cache[key] { return cached }
        let image = resolve(app) ?? fallbackIcon
        cache[key] = image
        return image
    }

    private func cacheKey(for app: AeroAppInfo) -> String {
        app.bundleId.map { "bundle:\($0)" } ?? "name:\(app.name)"
    }

    private func resolve(_ app: AeroAppInfo) -> NSImage? {
        if let bundleId = app.bundleId {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first,
               let icon = running.icon {
                return icon
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        return NSWorkspace.shared.runningApplications.first { $0.localizedName == app.name }?.icon
    }
}
