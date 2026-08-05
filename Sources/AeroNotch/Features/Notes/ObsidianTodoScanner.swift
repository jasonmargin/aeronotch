import Foundation
import OSLog

private let logger = Logger(subsystem: "aeronotch", category: "obsidian")

/// Discovers Obsidian vaults and scans their markdown files for `- [ ]` /
/// `- [x]` task lines, and writes checkbox toggles back into the files
/// (two-way sync — the vault stays the source of truth for these items).
///
/// All work is synchronous file I/O; callers run it off the main actor.
struct ObsidianTodoScanner: Sendable {
    /// Explicit vault paths from config (`notesVaultPaths`). When nil, vaults
    /// are auto-discovered (margindept-kb + Obsidian's own registry).
    let explicitVaultPaths: [String]?

    /// Directories never descended into during a scan.
    private static let skippedDirectories: Set<String> = [
        ".obsidian", ".git", ".trash", "node_modules", "target", "build",
    ]

    /// `- [ ] task`, `* [x] task`, `1. [ ] task`, with any indentation.
    private static let taskPattern = try! NSRegularExpression(
        pattern: #"^(\s*(?:[-*+]|\d+\.)\s+)\[([ xX])\]\s+(.*\S)\s*$"#
    )

    // MARK: - Vault discovery

    func discoverVaults() -> [URL] {
        if let explicitVaultPaths {
            return explicitVaultPaths
                .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
                .uniquedByPath()
        }

        var vaults: [URL] = []
        let fileManager = FileManager.default

        // The workspace knowledge base is always a vault worth scanning.
        let kb = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Code/margindept/margindept-kb")
        if fileManager.fileExists(atPath: kb.path) {
            vaults.append(kb)
        }

        // Obsidian's own vault registry.
        let registryFile = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/obsidian/obsidian.json")
        if let data = try? Data(contentsOf: registryFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let vaultDict = json["vaults"] as? [String: Any] {
            for value in vaultDict.values {
                guard let entry = value as? [String: Any],
                      let path = entry["path"] as? String,
                      fileManager.fileExists(atPath: path) else { continue }
                vaults.append(URL(fileURLWithPath: path))
            }
        }

        return vaults.uniquedByPath()
    }

    // MARK: - Scanning

    func scan() -> [ObsidianTodo] {
        discoverVaults().flatMap { scan(vault: $0) }
    }

    private func scan(vault: URL) -> [ObsidianTodo] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: vault,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var todos: [ObsidianTodo] = []
        let vaultName = vault.lastPathComponent

        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.dropFirst(vault.path.count + 1)
            let components = relativePath.split(separator: "/").map(String.init)
            if components.dropLast().contains(where: { Self.skippedDirectories.contains($0) }) {
                continue
            }
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            var insideFence = false
            for (index, line) in content.components(separatedBy: .newlines).enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    insideFence.toggle()
                    continue
                }
                guard !insideFence else { continue }
                guard let match = Self.taskPattern.firstMatch(
                    in: line,
                    range: NSRange(line.startIndex..., in: line)
                ), match.numberOfRanges == 4,
                   let stateRange = Range(match.range(at: 2), in: line),
                   let textRange = Range(match.range(at: 3), in: line) else { continue }

                todos.append(ObsidianTodo(
                    filePath: fileURL.path,
                    lineNumber: index + 1,
                    text: String(line[textRange]),
                    isDone: line[stateRange].lowercased() == "x",
                    vaultName: vaultName,
                    relativePath: String(relativePath)
                ))
            }
        }
        return todos
    }

    // MARK: - Write-back

    enum WriteBackError: Error {
        case taskNotFound
    }

    /// Flip the checkbox state of a task in its markdown file. Locates the
    /// line by scan-time line number first, falling back to a text search
    /// when the file shifted since the scan.
    func setCompleted(_ done: Bool, for todo: ObsidianTodo) throws {
        let url = URL(fileURLWithPath: todo.filePath)
        var lines = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: .newlines)

        let targetIndex = todo.lineNumber - 1
        if lines.indices.contains(targetIndex),
           let updated = Self.togglingCheckbox(in: lines[targetIndex], text: todo.text, done: done) {
            lines[targetIndex] = updated
        } else if let fallbackIndex = lines.firstIndex(where: {
            Self.togglingCheckbox(in: $0, text: todo.text, done: done) != nil
        }), let updated = Self.togglingCheckbox(in: lines[fallbackIndex], text: todo.text, done: done) {
            lines[fallbackIndex] = updated
        } else {
            logger.error("write-back: task not found in \(todo.filePath, privacy: .public)")
            throw WriteBackError.taskNotFound
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Rewrite the checkbox character of `line` when it is a task line whose
    /// text matches `text`. Returns nil when the line doesn't match.
    private static func togglingCheckbox(in line: String, text: String, done: Bool) -> String? {
        guard let match = taskPattern.firstMatch(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        ), match.numberOfRanges == 4,
           let stateRange = Range(match.range(at: 2), in: line),
           let textRange = Range(match.range(at: 3), in: line),
           line[textRange] == text else { return nil }

        var updated = line
        updated.replaceSubrange(stateRange, with: done ? "x" : " ")
        return updated
    }
}

private extension [URL] {
    func uniquedByPath() -> [URL] {
        var seen: Set<String> = []
        return filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
