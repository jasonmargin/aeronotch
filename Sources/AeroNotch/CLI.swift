import Foundation

/// Handles short-lived CLI invocations and exits before the app event loop starts.
///
/// The important one is `ping-workspace-change`: AeroSpace's
/// `exec-on-workspace-change` hook runs it on every switch, and it relays a
/// DistributedNotification to the running app instance (instant, no polling lag).
enum AeroNotchCLI {
    static func runAndExit(arguments: [String]) -> Never {
        switch arguments.first {
        case "ping-workspace-change":
            DistributedNotificationCenter.default().postNotificationName(
                Notifications.workspaceChanged,
                object: nil,
                deliverImmediately: true
            )
            exit(0)

        case "--version", "version":
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
            print("AeroNotch \(version)")
            exit(0)

        default:
            FileHandle.standardError.write(Data("usage: AeroNotch [ping-workspace-change | --version]\n".utf8))
            exit(64)
        }
    }
}
