import SwiftUI

/// The Notes drop-down: a quick-note scratch pad plus one combined to-do
/// list — app-created items first, then every `- [ ]` task discovered in the
/// user's Obsidian vaults (toggling those writes back to the markdown file).
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
                quickNote
                addRow
                todoList
            }
        }
        .onAppear { store.refresh() }
        .onExitCommand {
            if vm.isPinned {
                NSApp.keyWindow?.makeFirstResponder(nil)
            } else {
                vm.forceClose()
            }
        }
    }

    // MARK: - Header buttons

    private var headerButtons: some View {
        HStack(spacing: 2) {
            Button(action: { store.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(HeaderButtonStyle())
            .help("Rescan Obsidian vaults")
            Button(action: { vm.togglePinned() }) {
                Image(systemName: vm.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .medium))
                    .rotationEffect(.degrees(vm.isPinned ? 0 : 45))
            }
            .buttonStyle(HeaderButtonStyle(active: vm.isPinned))
            .help(vm.isPinned ? "Unpin — resume auto-hiding" : "Pin open on this screen")
        }
    }

    // MARK: - Quick note

    private var quickNote: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $store.quickNote)
                .font(.notch(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
            if store.quickNote.isEmpty {
                Text("Quick note…")
                    .font(.notch(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 13)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 58)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        }
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

    // MARK: - To-do list

    private var sortedAppTodos: [AppTodo] {
        store.appTodos.sorted { lhs, rhs in
            lhs.isDone != rhs.isDone ? !lhs.isDone : lhs.createdAt < rhs.createdAt
        }
    }

    private var obsidianByVault: [(vault: String, todos: [ObsidianTodo])] {
        Dictionary(grouping: store.obsidianTodos, by: \.vaultName)
            .map { (vault: $0.key, todos: $0.value.sorted { lhs, rhs in
                lhs.isDone != rhs.isDone
                    ? !lhs.isDone
                    : (lhs.relativePath != rhs.relativePath
                        ? lhs.relativePath < rhs.relativePath
                        : lhs.lineNumber < rhs.lineNumber)
            }) }
            .sorted { $0.vault < $1.vault }
    }

    private var todoList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                if store.appTodos.isEmpty && store.obsidianTodos.isEmpty {
                    Text("No to-dos yet")
                        .font(.notch(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12)
                }

                ForEach(sortedAppTodos) { todo in
                    AppTodoRow(
                        todo: todo,
                        onToggle: { store.toggle(todo) },
                        onDelete: { store.delete(todo) }
                    )
                }

                ForEach(obsidianByVault, id: \.vault) { group in
                    Text(group.vault)
                        .font(.notch(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .textCase(.uppercase)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    ForEach(group.todos) { todo in
                        ObsidianTodoRow(todo: todo, onToggle: { store.toggleObsidian(todo) })
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
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
                .fill(Color.white.opacity(isHovering ? 0.05 : 0))
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onToggle)
    }
}

private struct ObsidianTodoRow: View {
    let todo: ObsidianTodo
    let onToggle: () -> Void

    @State private var isHovering = false

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
                Text(todo.relativePath)
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
                .fill(Color.white.opacity(isHovering ? 0.05 : 0))
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onToggle)
        .help("\(todo.relativePath):\(todo.lineNumber)")
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    var active: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(active ? 0.95 : (configuration.isPressed ? 0.7 : 0.45)))
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(configuration.isPressed || active ? 0.12 : 0))
            }
    }
}
