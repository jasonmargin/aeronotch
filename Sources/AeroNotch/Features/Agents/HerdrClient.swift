import Foundation

enum HerdrError: Error {
    case binaryNotFound
    case commandFailed(Int32, String)
    case badOutput
}

/// Abstraction over the agent-session backend so the store/views don't care
/// whether state comes from herdr's CLI, a mock, or a future socket API.
protocol AgentSessionProviding: Sendable {
    func fetchSessions() async throws -> [AgentSession]
    func focus(paneID: String) async throws
}

/// Talks to herdr's CLI. `herdr agent list` emits a JSON envelope
/// (`{"result": {"agents": [...]}}`) with every tracked agent session and its
/// live status — herdr does all the detection work, we just poll it.
final class HerdrClient: AgentSessionProviding {
    private let binaryPath: String

    init(preferredPath: String? = nil) throws {
        var candidates: [String] = []
        if let preferredPath { candidates.append(preferredPath) }
        if let onPath = HerdrClient.findOnPATH("herdr") { candidates.append(onPath) }
        candidates.append(contentsOf: ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"])
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw HerdrError.binaryNotFound
        }
        binaryPath = path
    }

    func fetchSessions() async throws -> [AgentSession] {
        let out = try await run(["agent", "list"])
        guard let data = out.data(using: .utf8) else { throw HerdrError.badOutput }
        let envelope: AgentListEnvelope
        do {
            envelope = try JSONDecoder().decode(AgentListEnvelope.self, from: data)
        } catch {
            throw HerdrError.badOutput
        }
        return envelope.result.agents
            .map { dto in
                AgentSession(
                    agent: dto.agent,
                    status: AgentSession.Status(rawValue: dto.agentStatus) ?? .unknown,
                    cwd: dto.cwd ?? "",
                    paneID: dto.paneId,
                    focused: dto.focused ?? false
                )
            }
            // Stable order so the strip doesn't jitter between polls:
            // attention-worthy first, then agent name, then path.
            .sorted { lhs, rhs in
                if lhs.status.severity != rhs.status.severity {
                    return lhs.status.severity > rhs.status.severity
                }
                if lhs.agent != rhs.agent { return lhs.agent < rhs.agent }
                return lhs.cwd < rhs.cwd
            }
    }

    /// Jump the herdr window/tab/pane holding this session to the foreground.
    func focus(paneID: String) async throws {
        _ = try await run(["agent", "focus", paneID])
    }

    // MARK: - Process plumbing (mirrors AeroSpaceClient)

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
                    continuation.resume(throwing: HerdrError.commandFailed(-1, error.localizedDescription))
                    return
                }
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: outData, as: UTF8.self))
                } else {
                    continuation.resume(
                        throwing: HerdrError.commandFailed(
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

/// `herdr agent list` output: `{"id": "...", "result": {"agents": [...], "type": "agent_list"}}`.
private struct AgentListEnvelope: Decodable {
    let result: ResultPayload

    struct ResultPayload: Decodable {
        let agents: [AgentDTO]
    }

    struct AgentDTO: Decodable {
        let agent: String
        let agentStatus: String
        let cwd: String?
        let paneId: String
        let focused: Bool?

        enum CodingKeys: String, CodingKey {
            case agent, cwd, focused
            case agentStatus = "agent_status"
            case paneId = "pane_id"
        }
    }
}
