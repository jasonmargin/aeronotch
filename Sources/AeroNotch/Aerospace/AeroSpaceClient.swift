import Foundation

struct AeroAppInfo: Equatable, Hashable, Sendable {
    let name: String
    let bundleId: String?
}

/// An AeroSpace monitor and its AppKit bridge id.
struct MonitorInfo: Equatable, Sendable {
    /// AeroSpace's own monitor id.
    let id: Int
    /// 1-based index into `NSScreen.screens` (via `%{monitor-appkit-nsscreen-screens-id}`).
    let appkitScreenId: Int?
}

/// Immutable point-in-time view of AeroSpace state.
struct WorkspaceSnapshot: Equatable, Sendable {
    var workspaces: [String] = []
    var focused: String? = nil
    var appsByWorkspace: [String: [AeroAppInfo]] = [:]
    /// AeroSpace monitor-id → the workspace currently visible on that monitor.
    var visibleByMonitor: [Int: String] = [:]
    var monitors: [MonitorInfo] = []
}

enum AeroSpaceError: Error {
    case binaryNotFound
    case commandFailed(Int32, String)
    case badOutput
}

/// Abstraction over the workspace backend so the store/views don't care
/// whether state comes from AeroSpace's CLI, a mock, or a future IPC mechanism.
protocol WorkspaceProviding: Sendable {
    func fetchSnapshot() async throws -> WorkspaceSnapshot
    func switchTo(workspace: String) async throws
}

final class AeroSpaceClient: WorkspaceProviding {
    private let binaryPath: String

    init(preferredPath: String? = nil) throws {
        var candidates: [String] = []
        if let preferredPath { candidates.append(preferredPath) }
        if let onPath = AeroSpaceClient.findOnPATH("aerospace") { candidates.append(onPath) }
        candidates.append(contentsOf: ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"])
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AeroSpaceError.binaryNotFound
        }
        binaryPath = path
    }

    func fetchSnapshot() async throws -> WorkspaceSnapshot {
        async let allOut = run(["list-workspaces", "--all"])
        async let focusedOut = run(["list-workspaces", "--focused"])
        async let windowsOut = run([
            "list-windows", "--all", "--json", "--format",
            "%{window-id} %{window-title} %{app-name} %{app-bundle-id} %{workspace}"
        ])
        async let monitorsOut = run([
            "list-monitors", "--json", "--format",
            "%{monitor-id} %{monitor-name} %{monitor-appkit-nsscreen-screens-id}"
        ])

        let (all, focusedRaw, windowsJSON, monitorsJSON) = try await (allOut, focusedOut, windowsOut, monitorsOut)

        let workspaces = all
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let focused = focusedRaw.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        guard let data = windowsJSON.data(using: .utf8) else { throw AeroSpaceError.badOutput }
        let windows: [WindowDTO]
        do {
            windows = try JSONDecoder().decode([WindowDTO].self, from: data)
        } catch {
            throw AeroSpaceError.badOutput
        }

        var appsByWorkspace: [String: [AeroAppInfo]] = [:]
        for window in windows {
            let info = AeroAppInfo(name: window.appName, bundleId: window.appBundleId?.nilIfEmpty)
            var list = appsByWorkspace[window.workspace] ?? []
            if !list.contains(info) { list.append(info) }
            appsByWorkspace[window.workspace] = list
        }

        // Per-monitor visible workspaces (degrade gracefully — pills fall back
        // to the global focused workspace when this mapping is unavailable).
        var monitors: [MonitorInfo] = []
        var visibleByMonitor: [Int: String] = [:]
        if let monitorData = monitorsJSON.data(using: .utf8),
           let monitorDTOs = try? JSONDecoder().decode([MonitorDTO].self, from: monitorData),
           !monitorDTOs.isEmpty {
            monitors = monitorDTOs.map { MonitorInfo(id: $0.monitorId, appkitScreenId: $0.appkitScreenId) }
            visibleByMonitor = await self.visibleWorkspacesByMonitor(monitorDTOs)
        }

        return WorkspaceSnapshot(
            workspaces: workspaces,
            focused: focused,
            appsByWorkspace: appsByWorkspace,
            visibleByMonitor: visibleByMonitor,
            monitors: monitors
        )
    }

    /// Each monitor is queried independently — a single failure (transient CLI
    /// hiccup, display mid-reconfiguration) must not nuke the whole map.
    private func visibleWorkspacesByMonitor(_ monitors: [MonitorDTO]) async -> [Int: String] {
        await withTaskGroup(of: (Int, String?).self) { group in
            for monitor in monitors {
                group.addTask { [self] in
                    guard let out = try? await self.run([
                        "list-workspaces", "--monitor", String(monitor.monitorId), "--visible"
                    ]) else {
                        return (monitor.monitorId, nil)
                    }
                    return (monitor.monitorId, out.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
                }
            }
            var result: [Int: String] = [:]
            for await (id, workspace) in group {
                if let workspace { result[id] = workspace }
            }
            return result
        }
    }

    func switchTo(workspace: String) async throws {
        _ = try await run(["workspace", workspace])
    }

    // MARK: - Process plumbing

    private func run(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [binaryPath] in
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = arguments
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: AeroSpaceError.commandFailed(-1, error.localizedDescription))
                    return
                }
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: outData, as: UTF8.self))
                } else {
                    continuation.resume(
                        throwing: AeroSpaceError.commandFailed(
                            process.terminationStatus,
                            String(decoding: errData, as: UTF8.self)
                        )
                    )
                }
            }
        }
    }

    private static func findOnPATH(_ tool: String) -> String? {
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let path = String(dir) + "/" + tool
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

private struct WindowDTO: Decodable {
    let windowId: Int
    let windowTitle: String?
    let appName: String
    let appBundleId: String?
    let workspace: String

    enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case windowTitle = "window-title"
        case appName = "app-name"
        case appBundleId = "app-bundle-id"
        case workspace
    }
}

private struct MonitorDTO: Decodable {
    let monitorId: Int
    let monitorName: String?
    let appkitScreenId: Int?

    enum CodingKeys: String, CodingKey {
        case monitorId = "monitor-id"
        case monitorName = "monitor-name"
        case appkitScreenId = "monitor-appkit-nsscreen-screens-id"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
