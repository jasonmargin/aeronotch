import SwiftUI
import AppKit
import ServiceManagement

@main
struct AeroNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // CLI invocations (e.g. from AeroSpace's exec-on-workspace-change hook)
        // are short-lived: handle them before any app infrastructure starts.
        if CommandLine.arguments.count > 1 {
            AeroNotchCLI.runAndExit(arguments: Array(CommandLine.arguments.dropFirst()))
        }
    }

    var body: some Scene {
        MenuBarExtra("AeroNotch", systemImage: "rectangle.3.group") {
            MenuBarMenu(appDelegate: appDelegate)
        }
        Settings {
            SettingsWindowView(appDelegate: appDelegate)
        }
    }
}

private struct MenuBarMenu: View {
    let appDelegate: AppDelegate
    @Environment(\.openSettings) private var openSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")

        Divider()
        Button("Peek Workspaces") {
            appDelegate.peekAll(duration: 3)
        }
        .disabled(!appDelegate.hasNotches)

        Picker("Workspace Style", selection: Binding(
            get: { appDelegate.presentationMode },
            set: { appDelegate.setPresentationMode($0) }
        )) {
            Text("Notch").tag(AeroNotchConfig.PresentationMode.notch)
            Text("Menu Bar Strip").tag(AeroNotchConfig.PresentationMode.menuBarLeft)
        }

        Toggle("Peek on Workspace Switch", isOn: Binding(
            get: { appDelegate.peekOnWorkspaceSwitch },
            set: { appDelegate.setPeekOnWorkspaceSwitch($0) }
        ))

        Toggle("Agents", isOn: Binding(
            get: { appDelegate.agentsEnabled },
            set: { appDelegate.setAgentsEnabled($0) }
        ))

        Toggle("Agent Indicator", isOn: Binding(
            get: { appDelegate.agentsShowClosedIndicator },
            set: { appDelegate.setAgentsShowClosedIndicator($0) }
        ))
        .disabled(!appDelegate.agentsEnabled)

        Toggle("Notes", isOn: Binding(
            get: { appDelegate.notesEnabled },
            set: { appDelegate.setNotesEnabled($0) }
        ))

        Toggle("Notes Indicator", isOn: Binding(
            get: { appDelegate.notesShowClosedIndicator },
            set: { appDelegate.setNotesShowClosedIndicator($0) }
        ))
        .disabled(!appDelegate.notesEnabled)

        Toggle("Completion Widget", isOn: Binding(
            get: { appDelegate.completionWidgetEnabled },
            set: { appDelegate.setCompletionWidgetEnabled($0) }
        ))
        .disabled(!appDelegate.notesEnabled)

        Button("Open Notes") {
            appDelegate.openNotesDetail()
        }
        .disabled(!appDelegate.hasNotches || !appDelegate.notesEnabled)

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

        Divider()

        Button("Open Config File…") {
            appDelegate.revealConfig()
        }

        Divider()

        Text("AeroNotch \(appDelegate.versionString)")
            .foregroundStyle(.secondary)

        Button("Quit AeroNotch") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore(config: AeroNotchConfig.load())
    private let registry = NotchFeatureRegistry()

    private var config: AeroNotchConfig { settings.current }

    private var workspaceStore: WorkspaceStore?

    /// herdr agent-session tracking. Always injected into the view hierarchy;
    /// polling + panel registration are gated on `agentsEnabled` (live-toggleable).
    private lazy var agentStore: AgentSessionStore = {
        let client = try? HerdrClient(preferredPath: settings.current.herdrPath)
        return AgentSessionStore(client: client, config: settings.current)
    }()

    /// Notes notepad (app to-dos + quick note + Obsidian mirror). Always
    /// injected; registration is gated on `notesEnabled` (live-toggleable).
    private lazy var notesStore = NotesStore(config: settings.current)

    /// Read access for the settings window's Completed tab.
    var notes: NotesStore { notesStore }

    /// Desktop completion-heatmap widget (level: desktop, draggable).
    private let widgetController = CompletionWidgetController()

    /// One window + view model per screen, keyed by CoreGraphics display id.
    private var windows: [CGDirectDisplayID: NotchWindow] = [:]
    private var viewModels: [CGDirectDisplayID: NotchViewModel] = [:]

    private var screenObserver: NSObjectProtocol?
    private var agentsObserver: NSObjectProtocol?
    private var notesObserver: NSObjectProtocol?
    private var workspacesObserver: NSObjectProtocol?
    private var newTodoObserver: NSObjectProtocol?

    /// Local key-down monitor driving vim-style navigation (hjkl, Enter,
    /// `i`, `d`, Esc) whenever a notch panel is the key window.
    private var keyMonitor: Any?

    var hasNotches: Bool { !viewModels.isEmpty }

    var presentationMode: AeroNotchConfig.PresentationMode { settings.presentationMode }

    func setPresentationMode(_ mode: AeroNotchConfig.PresentationMode) {
        settings.setPresentationMode(mode)
    }

    var peekOnWorkspaceSwitch: Bool { settings.current.peekOnWorkspaceSwitch }

    func setPeekOnWorkspaceSwitch(_ value: Bool) {
        settings.setPeekOnWorkspaceSwitch(value)
    }

    var agentsEnabled: Bool { settings.current.agentsEnabled }

    func setAgentsEnabled(_ value: Bool) {
        settings.setAgentsEnabled(value)
    }

    var agentsShowClosedIndicator: Bool { settings.current.agentsShowClosedIndicator }

    func setAgentsShowClosedIndicator(_ value: Bool) {
        settings.setAgentsShowClosedIndicator(value)
    }

    var notesEnabled: Bool { settings.current.notesEnabled }

    func setNotesEnabled(_ value: Bool) {
        settings.setNotesEnabled(value)
    }

    var notesShowClosedIndicator: Bool { settings.current.notesShowClosedIndicator }

    func setNotesShowClosedIndicator(_ value: Bool) {
        settings.setNotesShowClosedIndicator(value)
    }

    var completionWidgetEnabled: Bool { settings.current.completionWidgetEnabled }

    func setCompletionWidgetEnabled(_ value: Bool) {
        settings.setCompletionWidgetEnabled(value)
    }

    var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let client = try? AeroSpaceClient(preferredPath: config.aerospacePath)
        let store = WorkspaceStore(client: client, config: config)
        workspaceStore = store

        // Workspace switch (hook ping or poll diff) → transient notch appearance,
        // only when enabled. The active workspace always shows in the strip
        // capsule; the notch itself opens on hover.
        store.onFocusedWorkspaceDidChange = { [weak self] in
            guard let self, self.settings.current.peekOnWorkspaceSwitch else { return }
            self.peekRelevantNotch()
        }

        registry.register(store)
        syncAgentsFeature(config)
        syncNotesFeature(config)
        syncWidget(config)

        // Settings changed via the menu → update view models + rebuild windows live.
        settings.onChange = { [weak self] config in
            self?.applyConfig(config)
        }

        rebuildWindows()
        applyPinnedFromConfig()

        agentsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notifications.agentsRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openAgentsDetail()
            }
        }

        notesObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notifications.notesRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openNotesDetail()
            }
        }

        workspacesObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notifications.workspacesRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openWorkspacesDetail()
            }
        }

        newTodoObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notifications.newTodoRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.focusNewTodo()
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildWindows()
            }
        }

        store.start()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleVimKey(event) else { return event }
            return nil
        }

        // One-time hello on every screen: prove the app is alive,
        // and teach where the notches live.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.peekAll(duration: 2.5)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspaceStore?.stop()
        agentStore.stop()
        notesStore.stop()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let agentsObserver {
            DistributedNotificationCenter.default().removeObserver(agentsObserver)
        }
        if let notesObserver {
            DistributedNotificationCenter.default().removeObserver(notesObserver)
        }
        if let workspacesObserver {
            DistributedNotificationCenter.default().removeObserver(workspacesObserver)
        }
        if let newTodoObserver {
            DistributedNotificationCenter.default().removeObserver(newTodoObserver)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    // MARK: - Settings

    private func applyConfig(_ config: AeroNotchConfig) {
        for viewModel in viewModels.values {
            viewModel.forceClose()
            viewModel.updateConfig(config)
        }
        syncAgentsFeature(config)
        syncNotesFeature(config)
        syncWidget(config)
        rebuildWindows()
        applyPinnedFromConfig()
    }

    /// Live on/off for the desktop completion widget.
    private func syncWidget(_ config: AeroNotchConfig) {
        if config.completionWidgetEnabled && config.notesEnabled {
            widgetController.show(store: notesStore)
        } else {
            widgetController.hide()
        }
    }

    /// Live on/off for the Agents feature: start/stop polling and add/remove
    /// the panel segment without a relaunch.
    private func syncAgentsFeature(_ config: AeroNotchConfig) {
        if config.agentsEnabled {
            registry.register(agentStore)
            agentStore.start()
        } else {
            registry.unregister(withID: agentStore.id)
            agentStore.stop()
        }
    }

    /// Live on/off for the Notes feature: start/stop vault scanning and
    /// add/remove the panel segment without a relaunch.
    private func syncNotesFeature(_ config: AeroNotchConfig) {
        if config.notesEnabled {
            registry.register(notesStore)
            notesStore.start()
        } else {
            registry.unregister(withID: notesStore.id)
            notesStore.stop()
        }
    }

    // MARK: - Peeking

    /// Expand every notch briefly (menu-bar action).
    func peekAll(duration: TimeInterval) {
        for viewModel in viewModels.values {
            viewModel.peek(duration: duration)
        }
    }

    /// Workspace switches peek on the screen holding the cursor — with
    /// AeroSpace's `move-mouse` focus callbacks, that's the screen the
    /// switch happened on. Falls back to all screens.
    private func peekRelevantNotch() {
        if let screen = NSScreen.screenWithMouse,
           let id = screen.displayID,
           let viewModel = viewModels[id] {
            viewModel.peek()
        } else {
            viewModels.values.forEach { $0.peek() }
        }
    }

    /// External `ping-agents`: toggle the Agents list on the screen holding
    /// the cursor (fallback: all screens) — opens it, or closes it when it's
    /// already showing Agents. Pinned cards always win (never closed here).
    private func openAgentsDetail() {
        toggleDetail(featureID: agentStore.id, peekDuration: 6)
    }

    /// Menu action or external `ping-notes`: toggle the Notes drop-down on
    /// the screen holding the cursor (fallback: all screens). Stays up while
    /// hovered or while it has keyboard focus (typing).
    func openNotesDetail() {
        toggleDetail(featureID: notesStore.id, peekDuration: 30)
    }

    /// External `ping-workspaces`: toggle the Workspaces grid on the screen
    /// holding the cursor (fallback: all screens).
    private func openWorkspacesDetail() {
        toggleDetail(featureID: workspaceStore?.id ?? "workspaces", peekDuration: 8)
    }

    /// External `ping-new-todo`: focus the add-a-to-do field in the Notes
    /// drop-down. Notes already showing → focus in place; otherwise open it
    /// (opening auto-focuses the field).
    private func focusNewTodo() {
        let target: NotchViewModel?
        if let screen = NSScreen.screenWithMouse,
           let id = screen.displayID {
            target = viewModels[id]
        } else {
            target = viewModels.values.first
        }
        if let target, target.state == .open, target.activeFeatureID == notesStore.id {
            notesStore.requestAddTodoFocus()
        } else {
            openNotesDetail()
        }
    }

    /// Shared toggle-behind-the-hotkey logic: when the panel is already open
    /// showing this feature, the same ping closes it; otherwise it deep-links,
    /// keys the window (vim navigation), and peeks. Pinned panels are never
    /// closed by a ping.
    private func toggleDetail(featureID: String, peekDuration: TimeInterval) {
        let targets: [NotchViewModel]
        if let screen = NSScreen.screenWithMouse,
           let id = screen.displayID,
           let viewModel = viewModels[id] {
            targets = [viewModel]
        } else {
            targets = Array(viewModels.values)
        }
        for viewModel in targets {
            if viewModel.state == .open, viewModel.activeFeatureID == featureID {
                viewModel.forceClose()
            } else {
                workspaceStore?.resetSelection()
                agentStore.resetSelection()
                notesStore.resetSelection()
                viewModel.openedViaPing = true
                viewModel.requestedFeatureID = featureID
                viewModel.peek(duration: peekDuration)
                viewModel.window?.makeKey()
            }
        }
    }

    // MARK: - Vim navigation

    /// Routes key-downs to the active card whenever a notch panel is the key
    /// window. Returns true when the event was consumed. Suspended while the
    /// Notes add-field is focused (letters must type normally) except Esc.
    private func handleVimKey(_ event: NSEvent) -> Bool {
        guard let viewModel = viewModels.values.first(where: { $0.window?.isKeyWindow == true }),
              viewModel.state == .open else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.isDisjoint(with: [.command, .control, .option]) else { return false }

        let feature = viewModel.activeFeatureID

        // Esc: blur the add field if typing (the field's own onExitCommand
        // handles it — don't consume), otherwise close the panel.
        if event.keyCode == 53 {
            if feature == notesStore.id, notesStore.isAddFieldFocused { return false }
            viewModel.forceClose()
            return true
        }

        // Everything else passes through untouched while typing.
        if feature == notesStore.id, notesStore.isAddFieldFocused { return false }

        // Enter: activate the selection (switch workspace / focus agent /
        // toggle to-do).
        if event.keyCode == 36 || event.keyCode == 76 {
            switch feature {
            case notesStore.id:
                notesStore.activateSelection()
            case agentStore.id:
                agentStore.activateSelection()
                viewModel.forceClose()
            default:
                workspaceStore?.activateSelection()
                viewModel.forceClose()
            }
            return true
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let workspacesID = workspaceStore?.id ?? "workspaces"
        switch (feature, key) {
        case (_, "j"):
            moveSelection(feature, by: feature == workspacesID ? WorkspacesFeatureView.maxPerRow : 1)
        case (_, "k"):
            moveSelection(feature, by: feature == workspacesID ? -WorkspacesFeatureView.maxPerRow : -1)
        case (workspacesID, "h"):
            workspaceStore?.moveSelection(by: -1)
        case (workspacesID, "l"):
            workspaceStore?.moveSelection(by: 1)
        case (notesStore.id, "i"):
            notesStore.requestAddTodoFocus()
        case (notesStore.id, "d"):
            notesStore.deleteSelection()
        default:
            return false
        }
        return true
    }

    private func moveSelection(_ feature: String, by delta: Int) {
        switch feature {
        case notesStore.id: notesStore.moveSelection(by: delta)
        case agentStore.id: agentStore.moveSelection(by: delta)
        default: workspaceStore?.moveSelection(by: delta)
        }
    }

    /// Re-apply the persisted pinned screen + feature after window rebuilds
    /// (launch, display changes, config reloads).
    private func applyPinnedFromConfig() {
        for (id, viewModel) in viewModels {
            viewModel.setPinned(config.pinnedDisplayID == id ? config.pinnedFeatureID : nil, notify: false)
        }
    }

    // MARK: - Window management (one notch per screen)

    private func rebuildWindows() {
        guard let workspaceStore else { return }
        let screens = NSScreen.screens
        let currentIDs = Set(screens.compactMap(\.displayID))

        // Tear down windows for disconnected displays.
        for (id, window) in windows where !currentIDs.contains(id) {
            window.close()
            windows.removeValue(forKey: id)
            viewModels.removeValue(forKey: id)
        }

        for screen in screens {
            guard let id = screen.displayID else { continue }

            // Menu-bar mode: the window spans from the screen's leading edge to
            // past the notch — far enough that the Agents panel can stay
            // *centered* on the notch. The region right of the notch is
            // transparent and hit-tests to nil (click-through).
            let windowSize: CGSize
            let windowX: CGFloat
            let windowHeight = max(config.openHeight, config.notesMaxHeight) + 40
            if config.presentationMode == .menuBarLeft {
                let exact = NotchMetrics.closedNotchSize(for: screen, overhang: 0)
                let notchSpan = max(exact.width, NotchContentView.panelMaxWidth)
                windowSize = CGSize(
                    width: screen.frame.width / 2 + notchSpan / 2 + 8,
                    height: windowHeight
                )
                windowX = screen.frame.minX
            } else {
                windowSize = CGSize(width: config.maxOpenWidth, height: windowHeight)
                windowX = screen.frame.midX - windowSize.width / 2
            }

            let viewModel: NotchViewModel
            if let existing = viewModels[id] {
                viewModel = existing
            } else {
                viewModel = NotchViewModel(config: config, screen: screen)
                viewModel.onPinChanged = { [weak self] featureID in
                    self?.settings.setPinned(displayID: featureID == nil ? nil : id, featureID: featureID)
                }
                viewModels[id] = viewModel
            }
            viewModel.refreshClosedNotchSize(for: screen)

            let window: NotchWindow
            if let existing = windows[id] {
                window = existing
            } else {
                window = NotchWindow(
                    contentRect: NSRect(origin: .zero, size: windowSize),
                    styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                    backing: .buffered,
                    defer: false
                )
                windows[id] = window
            }
            viewModel.window = window

            // Rebuild the hosting view so the per-screen environment stays correct.
            window.contentView = NSHostingView(
                rootView: NotchContentView()
                    .environmentObject(viewModel)
                    .environmentObject(registry)
                    .environmentObject(workspaceStore)
                    .environmentObject(agentStore)
                    .environmentObject(notesStore)
                    .environment(
                        \.aerospaceMonitorID,
                        workspaceStore.aerospaceMonitorID(forAppKitScreenIndex: screen.appKitScreenIndex)
                    )
            )
            window.setFrame(
                NSRect(
                    x: windowX,
                    y: screen.frame.maxY - windowSize.height,
                    width: windowSize.width,
                    height: windowSize.height
                ),
                display: false
            )
            window.orderFrontRegardless()
        }
    }

    // MARK: - Config

    func revealConfig() {
        let fileManager = FileManager.default
        let directory = AeroNotchConfig.configDirectory
        let file = AeroNotchConfig.configFile
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: file.path) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(AeroNotchConfig()) {
                try? data.write(to: file)
            }
        }
        NSWorkspace.shared.open(file)
    }
}
