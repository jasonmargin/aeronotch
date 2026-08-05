import Foundation

/// A to-do owned by the app (created in the notch, stored in
/// `~/.config/aeronotch/notes.json` — no Obsidian coupling).
struct AppTodo: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var text: String
    var isDone: Bool = false
    var createdAt: Date = Date()
}

/// A `- [ ]` task line discovered in an Obsidian vault markdown file.
/// Identified by file + line so toggles can write back to the exact spot;
/// `text` is kept as a fallback locator when the file shifted since the scan.
struct ObsidianTodo: Identifiable, Equatable, Sendable {
    var id: String { "\(filePath):\(lineNumber)" }
    let filePath: String
    /// 1-based line number at scan time.
    let lineNumber: Int
    let text: String
    let isDone: Bool
    /// Vault root name (for grouping in the UI).
    let vaultName: String
    /// Path relative to the vault root (for captions + disambiguation).
    let relativePath: String
}

/// On-disk payload for the app-owned notes store.
struct NotesData: Codable, Sendable {
    var todos: [AppTodo] = []
    var quickNote: String = ""
}
