import SwiftUI

/// The Notes drop-down: one combined to-do list — app-created items first,
/// then every `- [ ]` task discovered in the user's Obsidian vaults
/// (toggling those writes back to the markdown file), plus the completion
/// momentum heatmap.
///
/// Unlike the single-row Workspaces/Agents features this is a full panel: it
/// fills the taller notes height (see `AeroNotchConfig.notesMaxHeight`) and
/// keeps the notch open while it has keyboard focus, so moving the mouse
/// away mid-sentence never collapses it.
struct NotesFeatureView: View {
    @ObservedObject var store: NotesStore
    @EnvironmentObject private var vm: NotchViewModel

    @State private var newTodoText = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        FeaturePanel(
            featureID: store.id,
            title: "Notes",
            subtitle: store.openCount > 0 ? "\(store.openCount) open" : nil,
            trailing: AnyView(headerButtons)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                addRow
                momentum
                todoList
            }
        }
        .onAppear { store.refresh() }
        .onChange(of: store.addTodoFocusRequests) { _, _ in
            vm.window?.makeKey()
            addFieldFocused = true
        }
        .onChange(of: addFieldFocused) { _, focused in
            store.isAddFieldFocused = focused
        }
        .onChange(of: store.addFieldBlurRequests) { _, _ in
            addFieldFocused = false
        }
        .onExitCommand {
            if addFieldFocused {
                addFieldFocused = false
            } else if vm.isPinned {
                NSApp.keyWindow?.makeFirstResponder(nil)
            } else {
                vm.forceClose()
            }
        }
    }

    // MARK: - Header buttons

    private var headerButtons: some View {
        Button(action: { store.refresh() }) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .medium))
        }
        .buttonStyle(HeaderButtonStyle())
        .help("Rescan Obsidian vaults")
    }

    // MARK: - Add row

    private var addRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
            TextField("Add a to-do…", text: $newTodoText)
                .textFieldStyle(.plain)
                .font(.notch(size: 12))
                .focused($addFieldFocused)
                .onSubmit {
                    store.addTodo(newTodoText)
                    newTodoText = ""
                    addFieldFocused = true
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        }
    }

    // MARK: - Momentum heatmap

    private var momentum: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Momentum")
                .font(.notch(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .textCase(.uppercase)
            CompletionHeatmapView(tasksByDay: store.completedTasksByDay, weeks: 12)
        }
    }

    // MARK: - To-do list

    /// Renders the store's selectable list directly so the vim selection
    /// index always matches what's on screen. Vault headers are injected
    /// whenever the Obsidian item's vault changes (they aren't selectable).
    private var todoList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if store.appTodos.isEmpty && store.obsidianTodos.isEmpty {
                        Text("No to-dos yet")
                            .font(.notch(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 12)
                    }

                    let items = store.selectableTodos
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case .app(let todo):
                            AppTodoRow(
                                todo: todo,
                                isSelected: index == store.selectionIndex,
                                onToggle: { store.toggle(todo) },
                                onDelete: { store.delete(todo) }
                            )
                        case .obsidian(let todo):
                            if index == 0 || todo.vaultName != items[index - 1].vaultName {
                                Text(todo.vaultName)
                                    .font(.notch(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .textCase(.uppercase)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)
                            }
                            ObsidianTodoRow(
                                todo: todo,
                                isSelected: index == store.selectionIndex,
                                onToggle: { store.toggleObsidian(todo) }
                            )
                        }
                    }

                    if store.hasHiddenCompleted {
                        Button(action: { store.loadMoreCompleted() }) {
                            Text("Load completed from past \(store.completedWindowDays + 7) days")
                                .font(.notch(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.05))
                                }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            // Vim navigation: keep the selection in view while moving.
            .onChange(of: store.selectionIndex) { _, index in
                let items = store.selectableTodos
                guard items.indices.contains(index) else { return }
                withAnimation(.snappy(duration: 0.15)) {
                    proxy.scrollTo(items[index].id, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Rows

private struct Checkbox: View {
    let isDone: Bool

    var body: some View {
        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 13))
            .foregroundStyle(isDone ? Color.white.opacity(0.5) : Color.white.opacity(0.75))
            .contentShape(Rectangle())
    }
}

private struct AppTodoRow: View {
    let todo: AppTodo
    let isSelected: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Checkbox(isDone: todo.isDone)
            }
            .buttonStyle(.plain)
            Text(todo.text)
                .font(.notch(size: 12))
                .strikethrough(todo.isDone)
                .foregroundStyle(.white.opacity(todo.isDone ? 0.35 : 0.85))
                .lineLimit(2)
            Spacer(minLength: 4)
            if todo.isDone, let completedAt = todo.completedAt {
                Text(completedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.notch(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
            }
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(isSelected ? 0.1 : (isHovering ? 0.05 : 0)))
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onToggle)
    }
}

private struct ObsidianTodoRow: View {
    let todo: ObsidianTodo
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    private var caption: String {
        var caption = todo.relativePath
        if todo.isDone, let completedOn = todo.completedOn {
            caption += " · ✅ \(completedOn)"
        }
        return caption
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Checkbox(isDone: todo.isDone)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(todo.text)
                    .font(.notch(size: 12))
                    .strikethrough(todo.isDone)
                    .foregroundStyle(.white.opacity(todo.isDone ? 0.35 : 0.85))
                    .lineLimit(2)
                Text(caption)
                    .font(.notch(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(isSelected ? 0.1 : (isHovering ? 0.05 : 0)))
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onToggle)
        .help("\(todo.relativePath):\(todo.lineNumber)")
    }
}
