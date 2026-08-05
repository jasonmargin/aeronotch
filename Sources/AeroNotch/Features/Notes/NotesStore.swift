import Foundation
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "aeronotch", category: "notes")

/// Owns the Notes feature: app-created to-dos + a quick-note scratch pad
/// (persisted to `~/.config/aeronotch/notes.json`), plus a two-way mirror of
/// every `- [ ]` task found in the user's Obsidian vaults.
///
/// Polling shape mirrors AgentSessionStore: a timer, a serialized scan task,
/// and failure tolerance so a transient file error never blanks the list.
@MainActor
final class NotesStore: ObservableObject {
    static let featureID = "notes"

    @Published private(set) var appTodos: [AppTodo] = []
    @Published private(set) var obsidianTodos: [ObsidianTodo] = []
    @Published private(set) var vaultNames: [String] = []
    @Published var quickNote: String = "" {
        didSet { scheduleSave() }
    }

    /// Total open (unchecked) to-dos across both sources — drives the
    /// closed-notch indicator badge.
    var openCount: Int {
        appTodos.filter { !$0.isDone }.count + obsidianTodos.filter { !$0.isDone }.count
    }

    private let scanner: ObsidianTodoScanner
    private let scanInterval: TimeInterval

    private var pollTimer: Timer?
    private var scanTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    init(config: AeroNotchConfig) {
        self.scanner = ObsidianTodoScanner(explicitVaultPaths: config.notesVaultPaths)
        self.scanInterval = config.notesScanIntervalSeconds
        loadPersisted()
    }

    // MARK: - Lifecycle

    func start() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.requestScan()
            }
        }
        requestScan()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        scanTask?.cancel()
        scanTask = nil
        saveTask?.cancel()
        saveTask = nil
    }

    /// Rescan on demand (opening the popover, manual refresh button).
    func refresh() {
        requestScan()
    }

    // MARK: - App to-dos

    func addTodo(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appTodos.append(AppTodo(text: trimmed))
        scheduleSave()
    }

    func toggle(_ todo: AppTodo) {
        guard let index = appTodos.firstIndex(where: { $0.id == todo.id }) else { return }
        appTodos[index].isDone.toggle()
        scheduleSave()
    }

    func delete(_ todo: AppTodo) {
        appTodos.removeAll { $0.id == todo.id }
        scheduleSave()
    }

    // MARK: - Obsidian to-dos (two-way)

    func toggleObsidian(_ todo: ObsidianTodo) {
        let newState = !todo.isDone
        // Optimistic: flip locally, persist to the file, roll back on failure.
        if let index = obsidianTodos.firstIndex(where: { $0.id == todo.id }) {
            obsidianTodos[index] = ObsidianTodo(
                filePath: todo.filePath,
                lineNumber: todo.lineNumber,
                text: todo.text,
                isDone: newState,
                vaultName: todo.vaultName,
                relativePath: todo.relativePath
            )
        }
        let scanner = self.scanner
        Task.detached {
            do {
                try scanner.setCompleted(newState, for: todo)
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let index = self.obsidianTodos.firstIndex(where: { $0.id == todo.id }) {
                        self.obsidianTodos[index] = todo
                    }
                    self.requestScan()
                }
            }
        }
    }

    // MARK: - Scan pipeline (serialized on the main actor)

    private func requestScan() {
        guard scanTask == nil else { return }
        let scanner = self.scanner
        scanTask = Task { [weak self] in
            guard let self else { return }
            defer { self.scanTask = nil }
            async let todos = Task.detached { scanner.scan() }.value
            async let vaults = Task.detached { scanner.discoverVaults().map(\.lastPathComponent) }.value
            let (newTodos, newVaults) = await (todos, vaults)
            guard !Task.isCancelled else { return }
            if newTodos != self.obsidianTodos {
                self.obsidianTodos = newTodos
            }
            self.vaultNames = newVaults
        }
    }

    // MARK: - Persistence

    private static var storeFile: URL {
        AeroNotchConfig.configDirectory.appending(path: "notes.json")
    }

    private func loadPersisted() {
        guard let data = try? Data(contentsOf: Self.storeFile),
              let decoded = try? JSONDecoder().decode(NotesData.self, from: data) else { return }
        appTodos = decoded.todos
        quickNote = decoded.quickNote
    }

    /// Debounced save so typing in the quick note doesn't hit disk per keystroke.
    private func scheduleSave() {
        saveTask?.cancel()
        let payload = NotesData(todos: appTodos, quickNote: quickNote)
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                try FileManager.default.createDirectory(
                    at: AeroNotchConfig.configDirectory,
                    withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(payload).write(to: Self.storeFile, options: .atomic)
            } catch {
                logger.error("save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - NotchFeature conformance

extension NotesStore: NotchFeature {
    var id: String { Self.featureID }
    var displayName: String { "Notes" }

    func makeContentView() -> AnyView {
        AnyView(NotesFeatureView(store: self))
    }
}
