import Foundation
import Combine
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "aeronotch", category: "workspaces")

/// Keeps AeroSpace workspace state fresh and notifies the notch when the
/// focused workspace changes. Two signal paths:
///   1. Primary: `exec-on-workspace-change` hook → CLI ping → DistributedNotification.
///   2. Fallback: light polling (covers the hook not being installed).
@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var snapshot = WorkspaceSnapshot()
    @Published private(set) var isAvailable = true

    /// Fired when the focused workspace changed (or a hook ping arrived).
    var onFocusedWorkspaceDidChange: (() -> Void)?

    private let client: WorkspaceProviding?
    private let config: AeroNotchConfig

    private var pollTimer: Timer?
    private var distObserver: NSObjectProtocol?

    private var refreshTask: Task<Void, Never>?
    private var refreshPending = false
    private var forcePeekPending = false
    private var consecutiveFailures = 0

    init(client: WorkspaceProviding?, config: AeroNotchConfig) {
        self.client = client
        self.config = config
        self.isAvailable = client != nil
    }

    func start() {
        guard client != nil else { return }

        distObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notifications.workspaceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.requestRefresh(forcePeek: true)
            }
        }

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: config.pollIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.requestRefresh()
            }
        }

        requestRefresh()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let distObserver {
            DistributedNotificationCenter.default().removeObserver(distObserver)
        }
        distObserver = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    func switchToWorkspace(_ name: String, onMonitor monitorID: Int? = nil) {
        guard let client else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.switchTo(workspace: name)
                // Optimistic focus update so the pill highlight moves instantly;
                // the hook ping / next poll will reconcile real state.
                var optimistic = self.snapshot
                optimistic.focused = name
                if let monitorID {
                    optimistic.visibleByMonitor[monitorID] = name
                }
                self.snapshot = optimistic
            } catch {
                // Real state will be restored by the refresh below.
            }
            self.requestRefresh()
        }
    }

    /// Maps an AppKit screen (1-based `NSScreen.screens` index) to an AeroSpace
    /// monitor-id, preferring the bridge id reported by AeroSpace itself.
    func aerospaceMonitorID(forAppKitScreenIndex index: Int?) -> Int? {
        guard let index else { return nil }
        if let bridged = snapshot.monitors.first(where: { $0.appkitScreenId == index })?.id {
            return bridged
        }
        // Fallback: AeroSpace assigns monitor-ids in the same enumeration order.
        return index
    }

    func visibleWorkspaces(showEmpty: Bool, hidden: [String], alsoVisible extra: String? = nil) -> [String] {
        snapshot.workspaces.filter { workspace in
            guard !hidden.contains(workspace) else { return false }
            if showEmpty { return true }
            return workspace == snapshot.focused
                || workspace == extra
                || snapshot.appsByWorkspace[workspace]?.isEmpty == false
        }
    }

    // MARK: - Vim-nav selection

    /// Index into the displayed workspace list (grid, row-major).
    @Published var selectionIndex = 0

    /// The list the grid renders (and the keyboard navigates).
    var navigableWorkspaces: [String] {
        visibleWorkspaces(
            showEmpty: config.showEmptyWorkspaces,
            hidden: config.hiddenWorkspaces,
            alsoVisible: snapshot.focused
        )
    }

    func moveSelection(by delta: Int) {
        let count = navigableWorkspaces.count
        guard count > 0 else { return }
        selectionIndex = max(0, min(count - 1, selectionIndex + delta))
    }

    func resetSelection() {
        selectionIndex = 0
    }

    /// Enter: switch to the selected workspace.
    func activateSelection() {
        let list = navigableWorkspaces
        guard list.indices.contains(selectionIndex) else { return }
        switchToWorkspace(list[selectionIndex])
    }

    // MARK: - Refresh pipeline (serialized + coalesced on the main actor)

    private func requestRefresh(forcePeek: Bool = false) {
        refreshPending = true
        forcePeekPending = forcePeekPending || forcePeek
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            while self.refreshPending {
                let forcePeek = self.forcePeekPending
                self.refreshPending = false
                self.forcePeekPending = false
                await self.performRefresh(forcePeek: forcePeek)
                if Task.isCancelled { break }
            }
        }
    }

    private func performRefresh(forcePeek: Bool) async {
        guard let client else { return }
        do {
            let new = try await client.fetchSnapshot()
            let previousFocused = snapshot.focused
            snapshot = new
            consecutiveFailures = 0
            if !isAvailable { isAvailable = true }
            logger.info("snapshot: \(new.workspaces.count) workspaces, apps on \(new.appsByWorkspace.count): \(new.appsByWorkspace.keys.sorted().joined(separator: ","), privacy: .public), focused=\(new.focused ?? "nil", privacy: .public)")

            AppIconProvider.shared.preload(apps: new.appsByWorkspace.values.flatMap { $0 })

            // Never treat the first load as a "switch" (no peek at launch).
            if forcePeek || (previousFocused != nil && new.focused != previousFocused) {
                onFocusedWorkspaceDidChange?()
            }
        } catch AeroSpaceError.badOutput {
            // Transient parse hiccup — keep showing the last good snapshot.
        } catch {
            consecutiveFailures += 1
            // Hysteresis so a single failed CLI call doesn't blank the notch.
            if consecutiveFailures >= 2 {
                isAvailable = false
            }
        }
    }
}

// MARK: - NotchFeature conformance

extension WorkspaceStore: NotchFeature {
    var id: String { "workspaces" }
    var displayName: String { "Workspaces" }

    func makeContentView() -> AnyView {
        AnyView(WorkspacesFeatureView(store: self, config: config))
    }
}
