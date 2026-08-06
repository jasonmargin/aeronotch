import Foundation

/// A to-do owned by the app (created in the notch, stored in
/// `~/.config/aeronotch/notes.json` — no Obsidian coupling).
struct AppTodo: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var text: String
    var isDone: Bool = false
    var createdAt: Date = Date()
    /// When it was checked off (nil while open, or completed before this
    /// field existed).
    var completedAt: Date? = nil
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
    /// Completion date (`✅ yyyy-MM-dd`, Tasks-plugin convention) parsed
    /// from the line; written back on toggle.
    let completedOn: String?
    /// Vault root name (for grouping in the UI).
    let vaultName: String
    /// Path relative to the vault root (for captions + disambiguation).
    let relativePath: String
}

/// On-disk payload for the app-owned to-do store.
struct NotesData: Codable, Sendable {
    var todos: [AppTodo] = []
}
