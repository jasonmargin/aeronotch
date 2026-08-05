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
    }
}

private struct MenuBarMenu: View {
    let appDelegate: AppDelegate
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
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
    private let settings = SettingsStore(config: AeroNotchConfig.load())
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

    /// One window + view model per screen, keyed by CoreGraphics display id.
    private var windows: [CGDirectDisplayID: NotchWindow] = [:]
    private var viewModels: [CGDirectDisplayID: NotchViewModel] = [:]

    private var screenObserver: NSObjectProtocol?
    private var agentsObserver: NSObjectProtocol?
    private var notesObserver: NSObjectProtocol?

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
    }

    // MARK: - Settings

    private func applyConfig(_ config: AeroNotchConfig) {
        for viewModel in viewModels.values {
            viewModel.forceClose()
            viewModel.updateConfig(config)
        }
        syncAgentsFeature(config)
        syncNotesFeature(config)
        rebuildWindows()
        applyPinnedFromConfig()
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

    /// External `ping-agents`: transiently open the Agents detail popover on
    /// the screen holding the cursor (fallback: all screens).
    private func openAgentsDetail() {
        let targets: [NotchViewModel]
        if let screen = NSScreen.screenWithMouse,
           let id = screen.displayID,
           let viewModel = viewModels[id] {
            targets = [viewModel]
        } else {
            targets = Array(viewModels.values)
        }
        for viewModel in targets {
            viewModel.requestedFeatureID = agentStore.id
            viewModel.peek(duration: 6)
        }
    }

    /// Menu action or external `ping-notes`: open the Notes drop-down on the
    /// screen holding the cursor (fallback: all screens). Stays up while
    /// hovered or while it has keyboard focus (typing).
    func openNotesDetail() {
        let targets: [NotchViewModel]
        if let screen = NSScreen.screenWithMouse,
           let id = screen.displayID,
           let viewModel = viewModels[id] {
            targets = [viewModel]
        } else {
            targets = Array(viewModels.values)
        }
        for viewModel in targets {
            viewModel.requestedFeatureID = notesStore.id
            viewModel.peek(duration: 30)
        }
    }

    /// Re-apply the persisted pinned screen after window rebuilds (launch,
    /// display changes, config reloads).
    private func applyPinnedFromConfig() {
        for (id, viewModel) in viewModels {
            viewModel.setPinned(config.notesPinnedDisplayID == id, notify: false)
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
                viewModel.onPinChanged = { [weak self] pinned in
                    self?.settings.setNotesPinnedDisplay(pinned ? id : nil)
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
