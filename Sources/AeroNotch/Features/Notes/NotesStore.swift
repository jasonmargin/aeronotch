import Foundation
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "aeronotch", category: "notes")

/// Owns the Notes feature: app-created to-dos (persisted to
/// `~/.config/aeronotch/notes.json`), plus a two-way mirror of every
/// `- [ ]` task found in the user's Obsidian vaults.
///
/// Polling shape mirrors AgentSessionStore: a timer, a serialized scan task,
/// and failure tolerance so a transient file error never blanks the list.
@MainActor
final class NotesStore: ObservableObject {
    static let featureID = "notes"

    @Published private(set) var appTodos: [AppTodo] = []
    @Published private(set) var obsidianTodos: [ObsidianTodo] = []
    @Published private(set) var vaultNames: [String] = []

    /// Total open (unchecked) to-dos across both sources — drives the
    /// closed-notch indicator badge.
    var openCount: Int {
        appTodos.filter { !$0.isDone }.count + obsidianTodos.filter { !$0.isDone }.count
    }

    /// How far back completed to-dos are shown (days). Starts at 7; the
    /// "load more" button extends it in 7-day increments.
    @Published private(set) var completedWindowDays = 7

    /// Incremented to ask the Notes view to focus the add-a-to-do field
    /// (hotkey: ping-new-todo, or `i` in vim mode).
    @Published private(set) var addTodoFocusRequests = 0

    func requestAddTodoFocus() {
        addTodoFocusRequests += 1
    }

    /// A selectable row in the to-do list, in display order: app to-dos
    /// first (open oldest→newest, then done newest→oldest), then Obsidian
    /// tasks grouped by vault (same ordering within each group).
    enum SelectableTodo: Equatable, Identifiable {
        case app(AppTodo)
        case obsidian(ObsidianTodo)

        var id: String {
            switch self {
            case .app(let todo): return "app-\(todo.id.uuidString)"
            case .obsidian(let todo): return "obs-\(todo.id)"
            }
        }

        /// Vault name for Obsidian items (app to-dos have no vault) — used
        /// to inject group headers while rendering.
        var vaultName: String? {
            guard case .obsidian(let todo) = self else { return nil }
            return todo.vaultName
        }
    }

    /// Display order shared by the card and the vim keyboard navigation.
    var selectableTodos: [SelectableTodo] {
        let apps = visibleAppTodos
            .sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone }
                if lhs.isDone {
                    return (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
                }
                return lhs.createdAt < rhs.createdAt
            }
            .map(SelectableTodo.app)
        let obsidian = visibleObsidianTodos
            .sorted { lhs, rhs in
                if lhs.vaultName != rhs.vaultName { return lhs.vaultName < rhs.vaultName }
                if lhs.isDone != rhs.isDone { return !lhs.isDone }
                if lhs.isDone { return (lhs.completedOn ?? "") > (rhs.completedOn ?? "") }
                return lhs.relativePath != rhs.relativePath
                    ? lhs.relativePath < rhs.relativePath
                    : lhs.lineNumber < rhs.lineNumber
            }
            .map(SelectableTodo.obsidian)
        return apps + obsidian
    }

    // MARK: - Vim-nav selection

    /// Index into `selectableTodos`.
    @Published var selectionIndex = 0

    /// True while the add-a-to-do field has focus (vim keys stay off then).
    @Published var isAddFieldFocused = false

    /// Incremented to ask the view to blur the add field (Esc while typing).
    @Published private(set) var addFieldBlurRequests = 0

    func requestAddFieldBlur() {
        addFieldBlurRequests += 1
    }

    func moveSelection(by delta: Int) {
        let count = selectableTodos.count
        guard count > 0 else { return }
        selectionIndex = max(0, min(count - 1, selectionIndex + delta))
    }

    func resetSelection() {
        selectionIndex = 0
    }

    /// Enter: toggle done on the selected to-do.
    func activateSelection() {
        let list = selectableTodos
        guard list.indices.contains(selectionIndex) else { return }
        switch list[selectionIndex] {
        case .app(let todo): toggle(todo)
        case .obsidian(let todo): toggleObsidian(todo)
        }
    }

    /// `d`: delete the selected to-do (app-owned only — Obsidian tasks are
    /// never deleted from the vault via the keyboard).
    func deleteSelection() {
        let list = selectableTodos
        guard list.indices.contains(selectionIndex),
              case .app(let todo) = list[selectionIndex] else { return }
        delete(todo)
    }

    func loadMoreCompleted() {
        completedWindowDays += 7
    }

    /// App to-dos with completed ones limited to the current window.
    /// Undated completions (pre-timestamp data) are hidden.
    var visibleAppTodos: [AppTodo] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(completedWindowDays) * 86_400)
        return appTodos.filter { !$0.isDone || ($0.completedAt.map { $0 >= cutoff } ?? false) }
    }

    /// Obsidian tasks with completed ones limited to the current window.
    /// Completed tasks without a `✅` date are hidden (age unknown).
    var visibleObsidianTodos: [ObsidianTodo] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -completedWindowDays, to: Date()) ?? Date()
        let cutoffString = ObsidianTodoScanner.dateString(for: cutoff)
        return obsidianTodos.filter { !$0.isDone || ($0.completedOn.map { $0 >= cutoffString } ?? false) }
    }

    /// True when completed to-dos exist beyond the current window — drives
    /// the "load more" button.
    var hasHiddenCompleted: Bool {
        appTodos.filter(\.isDone).count > visibleAppTodos.filter(\.isDone).count
            || obsidianTodos.filter(\.isDone).count > visibleObsidianTodos.filter(\.isDone).count
    }

    /// A completed to-do from either source, for the Completed settings tab.
    struct CompletedTodoItem: Identifiable, Equatable {
        let id: String
        let text: String
        let source: String
        let completedOn: Date?
    }

    /// Every completed to-do (no window), newest first, undated last.
    var allCompleted: [CompletedTodoItem] {
        let app = appTodos.filter(\.isDone).map {
            CompletedTodoItem(id: $0.id.uuidString, text: $0.text, source: "AeroNotch", completedOn: $0.completedAt)
        }
        let obsidian = obsidianTodos.filter(\.isDone).map {
            CompletedTodoItem(
                id: $0.id,
                text: $0.text,
                source: $0.vaultName,
                completedOn: $0.completedOn.flatMap { ObsidianTodoScanner.date(from: $0) }
            )
        }
        return (app + obsidian).sorted {
            ($0.completedOn ?? .distantPast) > ($1.completedOn ?? .distantPast)
        }
    }

    /// Day (`yyyy-MM-dd`) → completed task texts, across both sources.
    /// Drives the contribution heatmap (notch card, Completed tab, widget).
    var completedTasksByDay: [String: [String]] {
        var map: [String: [String]] = [:]
        for item in allCompleted {
            guard let date = item.completedOn else { continue }
            map[ObsidianTodoScanner.dateString(for: date), default: []].append(item.text)
        }
        return map
    }

    /// Day (`yyyy-MM-dd`) → number of completions.
    var completionsByDay: [String: Int] {
        completedTasksByDay.mapValues(\.count)
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
        appTodos[index].completedAt = appTodos[index].isDone ? Date() : nil
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
                completedOn: newState ? ObsidianTodoScanner.todayString() : nil,
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
            self.selectionIndex = min(self.selectionIndex, max(0, self.selectableTodos.count - 1))
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
    }

    /// Debounced save so rapid toggles don't hit disk per tap.
    private func scheduleSave() {
        saveTask?.cancel()
        let payload = NotesData(todos: appTodos)
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
