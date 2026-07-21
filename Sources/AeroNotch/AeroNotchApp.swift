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

        Picker("Popover Style", selection: Binding(
            get: { appDelegate.presentationMode },
            set: { appDelegate.setPresentationMode($0) }
        )) {
            Text("Notch").tag(AeroNotchConfig.PresentationMode.notch)
            Text("Menu Bar Strip").tag(AeroNotchConfig.PresentationMode.menuBarLeft)
        }

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

    /// One window + view model per screen, keyed by CoreGraphics display id.
    private var windows: [CGDirectDisplayID: NotchWindow] = [:]
    private var viewModels: [CGDirectDisplayID: NotchViewModel] = [:]

    private var screenObserver: NSObjectProtocol?

    var hasNotches: Bool { !viewModels.isEmpty }

    var presentationMode: AeroNotchConfig.PresentationMode { settings.presentationMode }

    func setPresentationMode(_ mode: AeroNotchConfig.PresentationMode) {
        settings.setPresentationMode(mode)
    }

    var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let client = try? AeroSpaceClient(preferredPath: config.aerospacePath)
        let store = WorkspaceStore(client: client, config: config)
        workspaceStore = store

        // Workspace switch (hook ping or poll diff) → transient notch appearance.
        store.onFocusedWorkspaceDidChange = { [weak self] in
            self?.peekRelevantNotch()
        }

        registry.register(store)

        // Settings changed via the menu → update view models + rebuild windows live.
        settings.onChange = { [weak self] config in
            self?.applyConfig(config)
        }

        rebuildWindows()

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
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: - Settings

    private func applyConfig(_ config: AeroNotchConfig) {
        for viewModel in viewModels.values {
            viewModel.forceClose()
            viewModel.updateConfig(config)
        }
        rebuildWindows()
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

    // MARK: - Window management (one notch per screen)

    private func rebuildWindows() {
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

            // Menu-bar mode: the window spans only what the strip can ever occupy —
            // its trailing edge stops at the notch's right edge, so nothing right
            // of the notch is ever covered. Notch mode: centered fixed-width window.
            let windowSize: CGSize
            let windowX: CGFloat
            if config.presentationMode == .menuBarLeft {
                let exact = NotchMetrics.closedNotchSize(for: screen, overhang: 0)
                windowSize = CGSize(
                    width: screen.frame.width / 2 + exact.width / 2 + 8,
                    height: config.openHeight + 40
                )
                windowX = screen.frame.minX
            } else {
                windowSize = CGSize(width: config.maxOpenWidth, height: config.openHeight + 40)
                windowX = screen.frame.midX - windowSize.width / 2
            }

            let viewModel: NotchViewModel
            if let existing = viewModels[id] {
                viewModel = existing
            } else {
                viewModel = NotchViewModel(config: config, screen: screen)
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

            // Rebuild the hosting view so the per-screen environment stays correct.
            window.contentView = NSHostingView(
                rootView: NotchContentView()
                    .environmentObject(viewModel)
                    .environmentObject(registry)
                    .environment(
                        \.aerospaceMonitorID,
                        workspaceStore?.aerospaceMonitorID(forAppKitScreenIndex: screen.appKitScreenIndex)
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
