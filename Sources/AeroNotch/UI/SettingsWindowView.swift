import SwiftUI
import ServiceManagement

/// Preferences + completed-task browser, opened from the menu bar (⌘,).
/// Settings bind straight to SettingsStore (live-applied and persisted to
/// config.json); Completed lists every finished to-do from both sources
/// without the drop-down's 7-day window.
struct SettingsWindowView: View {
    let appDelegate: AppDelegate

    var body: some View {
        TabView {
            SettingsTab(appDelegate: appDelegate)
                .tabItem { Label("Settings", systemImage: "gear") }
            CompletedTasksTab(store: appDelegate.notes)
                .tabItem { Label("Completed", systemImage: "checkmark.circle") }
        }
        .frame(width: 460, height: 470)
    }
}

// MARK: - Settings tab

private struct SettingsTab: View {
    let appDelegate: AppDelegate
    @ObservedObject var settings: SettingsStore

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.settings = appDelegate.settings
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
                Picker("Workspace Style", selection: binding(\.presentationMode, settings.setPresentationMode)) {
                    Text("Notch").tag(AeroNotchConfig.PresentationMode.notch)
                    Text("Menu Bar Strip").tag(AeroNotchConfig.PresentationMode.menuBarLeft)
                }
                Toggle("Peek on Workspace Switch", isOn: binding(\.peekOnWorkspaceSwitch, settings.setPeekOnWorkspaceSwitch))
                LabeledContent("Hover Open Delay") {
                    Slider(
                        value: binding(\.hoverOpenDelaySeconds, settings.setHoverOpenDelaySeconds),
                        in: 0...0.5,
                        step: 0.02
                    ) {
                        Text("\(settings.current.hoverOpenDelaySeconds, format: .number.precision(.fractionLength(2)))s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }

            Section("Workspaces") {
                Toggle("Show Empty Workspaces", isOn: binding(\.showEmptyWorkspaces, settings.setShowEmptyWorkspaces))
                Toggle("Show App Icons", isOn: binding(\.showAppIcons, settings.setShowAppIcons))
            }

            Section("Agents") {
                Toggle("Agents", isOn: binding(\.agentsEnabled, settings.setAgentsEnabled))
                Toggle("Agent Indicator", isOn: binding(\.agentsShowClosedIndicator, settings.setAgentsShowClosedIndicator))
                    .disabled(!settings.current.agentsEnabled)
            }

            Section("Notes") {
                Toggle("Notes", isOn: binding(\.notesEnabled, settings.setNotesEnabled))
                Toggle("Notes Indicator", isOn: binding(\.notesShowClosedIndicator, settings.setNotesShowClosedIndicator))
                    .disabled(!settings.current.notesEnabled)
                Toggle("Completion Widget", isOn: binding(\.completionWidgetEnabled, settings.setCompletionWidgetEnabled))
                    .disabled(!settings.current.notesEnabled)
                LabeledContent("Obsidian Vaults") {
                    Text(appDelegate.notes.vaultNames.isEmpty ? "None found" : appDelegate.notes.vaultNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                Button("Open Config File…") {
                    appDelegate.revealConfig()
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Live two-way binding into SettingsStore: reads the current config,
    /// writes through the setter (persists + rebuilds windows).
    private func binding<T: Equatable>(
        _ keyPath: KeyPath<AeroNotchConfig, T>,
        _ setter: @escaping (T) -> Void
    ) -> Binding<T> {
        Binding(
            get: { settings.current[keyPath: keyPath] },
            set: { setter($0) }
        )
    }
}

// MARK: - Completed tasks tab

private struct CompletedTasksTab: View {
    @ObservedObject var store: NotesStore

    private struct Section_ {
        let title: String
        let items: [NotesStore.CompletedTodoItem]
    }

    /// Day-grouped sections, newest first; undated completions last.
    private var sections: [Section_] {
        var byDay: [String: [NotesStore.CompletedTodoItem]] = [:]
        var undated: [NotesStore.CompletedTodoItem] = []
        for item in store.allCompleted {
            if let date = item.completedOn {
                byDay[ObsidianTodoScanner.dateString(for: date), default: []].append(item)
            } else {
                undated.append(item)
            }
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        var result = byDay.keys.sorted(by: >).map { key in
            Section_(
                title: ObsidianTodoScanner.date(from: key).map { dateFormatter.string(from: $0) } ?? key,
                items: byDay[key] ?? []
            )
        }
        if !undated.isEmpty {
            result.append(Section_(title: "Unknown date", items: undated))
        }
        return result
    }

    var body: some View {
        Group {
            if store.allCompleted.isEmpty {
                ContentUnavailableView(
                    "No completed to-dos",
                    systemImage: "checkmark.circle",
                    description: Text("Checked-off to-dos from AeroNotch and Obsidian show up here.")
                )
            } else {
                VStack(spacing: 0) {
                    CompletionHeatmapView(tasksByDay: store.completedTasksByDay, weeks: 20, cell: 12)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    List {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            Section(section.title) {
                                ForEach(section.items) { item in
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                        Text(item.text)
                                            .strikethrough()
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                        Spacer(minLength: 4)
                                        Text(item.source)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
    }
}
