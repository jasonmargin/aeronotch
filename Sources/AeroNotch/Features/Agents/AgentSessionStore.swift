import Foundation
import Combine
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "aeronotch", category: "agents")

/// Keeps the herdr agent-session list fresh via light polling, mirroring
/// WorkspaceStore's shape: a timer, a serialized refresh task, and failure
/// hysteresis so one bad CLI call doesn't blank the indicator.
@MainActor
final class AgentSessionStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var isAvailable = true

    private let client: (any AgentSessionProviding)?
    private let config: AeroNotchConfig

    private var pollTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    init(client: (any AgentSessionProviding)?, config: AeroNotchConfig) {
        self.client = client
        self.config = config
        self.isAvailable = client != nil
        if client == nil {
            logger.error("herdr binary not found — agents feature inert")
        }
    }

    func start() {
        guard client != nil else { return }
        logger.info("polling herdr every \(self.config.agentsPollIntervalSeconds, privacy: .public)s")

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: config.agentsPollIntervalSeconds,
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
        refreshTask?.cancel()
        refreshTask = nil
        // Blank immediately so the strip/panel clear on live disable.
        sessions = []
        consecutiveFailures = 0
    }

    /// Jump to the herdr pane running this session.
    func focus(_ session: AgentSession) {
        guard let client else { return }
        Task {
            try? await client.focus(paneID: session.paneID)
        }
    }

    // MARK: - Refresh pipeline (serialized on the main actor)

    private func requestRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            await self.performRefresh()
        }
    }

    private func performRefresh() async {
        guard let client, !Task.isCancelled else { return }
        do {
            let new = try await client.fetchSessions()
            if new != sessions {
                logger.info("\(new.count, privacy: .public) session(s): \(new.map { "\($0.agent)=\($0.status.rawValue)" }.joined(separator: ", "), privacy: .public)")
                sessions = new
            }
            consecutiveFailures = 0
            if !isAvailable { isAvailable = true }
        } catch HerdrError.badOutput {
            // Transient parse hiccup — keep showing the last good list.
            logger.error("poll: bad output (keeping last list)")
        } catch {
            consecutiveFailures += 1
            logger.error("poll failed (\(self.consecutiveFailures, privacy: .public)x): \(error.localizedDescription, privacy: .public)")
            // Hysteresis so a single failed CLI call doesn't blank the strip.
            if consecutiveFailures >= 2 {
                isAvailable = false
                sessions = []
            }
        }
    }
}

// MARK: - NotchFeature conformance

extension AgentSessionStore: NotchFeature {
    var id: String { "agents" }
    var displayName: String { "Agents" }

    func makeContentView() -> AnyView {
        AnyView(AgentsFeatureView(store: self))
    }
}
