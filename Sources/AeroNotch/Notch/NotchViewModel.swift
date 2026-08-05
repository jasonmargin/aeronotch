import SwiftUI
import Combine
import OSLog

private let stateLogger = Logger(subsystem: "aeronotch", category: "state")

/// Owns the notch's expansion state and every timer that can change it.
/// Three ways the notch opens:
///   1. `peek()`      – transient appearance (workspace switch); auto-closes unless hovered.
///   2. hover          – small delay, then stays open while the cursor is over it.
///   3. `handleTap()`  – tap on the closed notch opens it.
@MainActor
final class NotchViewModel: ObservableObject {
    enum NotchState {
        case closed
        case open
    }

    @Published private(set) var state: NotchState = .closed
    @Published private(set) var isHovering = false

    /// Pinned open (Notes): the notch stays expanded on this screen until
    /// unpinned — peeks, hover-exits, and config reloads never close it.
    @Published private(set) var isPinned = false

    /// The window hosting this view model (set by AppDelegate) — used to
    /// allow keyboard focus while the Notes panel is up (text input needs a
    /// key window) and to resist closing while the user is typing.
    weak var window: NotchWindow?

    /// Called after a pin toggle so AppDelegate can persist the pinned screen.
    var onPinChanged: ((Bool) -> Void)?

    @Published var closedNotchSize: CGSize

    /// Exact (zero-overhang) notch width — used in menuBarLeft mode where the
    /// placeholder must never bleed past the hardware notch's right edge.
    @Published private(set) var exactClosedNotchWidth: CGFloat

    /// Ideal content widths reported live by each feature (keyed by feature
    /// id), so switching features never shows the other's stale width.
    @Published private(set) var openContentWidths: [String: CGFloat] = [:]

    /// Ideal content heights reported live by each feature (keyed by feature
    /// id) — lets list-style features (Agents, Notes) hug their rows.
    @Published private(set) var openContentHeights: [String: CGFloat] = [:]

    /// Feature shown when nothing was deep-linked (registration order default).
    var defaultFeatureID = "workspaces"

    func reportOpenContentWidth(_ width: CGFloat, for featureID: String) {
        let current = openContentWidths[featureID] ?? 0
        guard abs(current - width) > 0.5 else { return }
        openContentWidths[featureID] = width
    }

    func reportOpenContentHeight(_ height: CGFloat, for featureID: String) {
        let current = openContentHeights[featureID] ?? 0
        guard abs(current - height) > 0.5 else { return }
        openContentHeights[featureID] = height
    }

    /// Feature the next open should preselect (e.g. the agent strip deep-links
    /// to Agents). One-shot: cleared on close.
    @Published var requestedFeatureID: String? {
        didSet { updateKeyboardFocus() }
    }

    /// The feature whose content the open panel shows right now: a transient
    /// hover overlay first (agents strip hovered while Notes is pinned),
    /// then Notes while pinned, then the deep-linked feature.
    var activeFeatureID: String {
        temporaryFeatureID ?? (isPinned ? NotesStore.featureID : (requestedFeatureID ?? defaultFeatureID))
    }

    /// Transient content override: while Notes is pinned, hovering the agents
    /// strip shows the Agents list *over* the notes panel without disturbing
    /// the pin. Cleared on hover-out.
    @Published var temporaryFeatureID: String?

    /// True while the Notes panel is up — drives the taller open height and
    /// the close-resistance (never collapse while the user is typing).
    var isShowingNotes: Bool {
        state == .open && activeFeatureID == NotesStore.featureID
    }

    /// Open height for the active feature: a pinned screen holds the notepad
    /// height even under a hover overlay (so the panel never jumps); a
    /// reported content height — plus the reserved hardware-notch strip,
    /// which is carved out of the panel's top — clamped between the
    /// single-row default and the notepad cap; Notes defaults to the tall
    /// notepad, others to the standard popover height.
    var effectiveOpenHeight: CGFloat {
        if isPinned { return config.notesMaxHeight }
        if let reported = openContentHeights[activeFeatureID] {
            return min(
                max(reported + closedNotchSize.height, maxOpenSize.height),
                config.notesMaxHeight
            )
        }
        return activeFeatureID == NotesStore.featureID ? config.notesMaxHeight : maxOpenSize.height
    }

    /// Presentation mode for the expanded popover.
    var presentationMode: AeroNotchConfig.PresentationMode { config.presentationMode }

    /// Width of the screen this notch lives on (tracked for strip/band sizing).
    private(set) var screenWidth: CGFloat

    /// Panel width when open (notch mode): the shared card width plus side
    /// margins, clamped between a minimum and the configured cap. Features
    /// that report an ideal width override the card default.
    var effectiveOpenWidth: CGFloat {
        let content = openContentWidths[requestedFeatureID ?? defaultFeatureID] ?? FeaturePanelMetrics.contentWidth
        return min(max(content + 64, closedNotchSize.width + 80), config.maxOpenWidth)
    }

    /// Maximum expanded size (notch mode) — the window is created at this size.
    /// Height never lets content dip into the hardware-notch strip.
    var maxOpenSize: CGSize {
        CGSize(
            width: config.maxOpenWidth,
            height: max(config.openHeight, closedNotchSize.height + 30)
        )
    }

    /// Live config (updated when the user changes settings via the menu).
    @Published private(set) var config: AeroNotchConfig

    private var peekTask: Task<Void, Never>?
    private var hoverOpenTask: Task<Void, Never>?
    private var hoverCloseTask: Task<Void, Never>?

    init(config: AeroNotchConfig, screen: NSScreen?) {
        self.config = config
        self.closedNotchSize = NotchMetrics.closedNotchSize(for: screen)
        self.exactClosedNotchWidth = NotchMetrics.closedNotchSize(for: screen, overhang: 0).width
        self.screenWidth = screen?.frame.width ?? 1440
    }

    func updateConfig(_ config: AeroNotchConfig) {
        self.config = config
    }

    func refreshClosedNotchSize(for screen: NSScreen?) {
        closedNotchSize = NotchMetrics.closedNotchSize(for: screen)
        exactClosedNotchWidth = NotchMetrics.closedNotchSize(for: screen, overhang: 0).width
        if let screen { screenWidth = screen.frame.width }
    }

    // MARK: - Open / Close

    /// Never collapse while pinned, or while the Notes panel has keyboard
    /// focus (mouse leaving mid-sentence must not destroy typed input).
    private var shouldResistClose: Bool {
        isPinned || (isShowingNotes && (window?.isKeyWindow ?? false))
    }

    func open() {
        cancelPeek()
        hoverCloseTask?.cancel()
        state = .open
        updateKeyboardFocus()
        stateLogger.info("open() feature=\(self.requestedFeatureID ?? "nil", privacy: .public)")
    }

    /// Closes only when the cursor isn't over the notch.
    func close() {
        guard !isHovering, !shouldResistClose else { return }
        forceClose()
    }

    func forceClose() {
        guard !isPinned else { return }
        cancelPeek()
        temporaryFeatureID = nil
        state = .closed
        updateKeyboardFocus()
        stateLogger.info("forceClose()")
    }

    /// Transient expansion for workspace switches. Restarts its own timer on
    /// repeat calls, so rapid switches keep the notch up continuously.
    /// Ignored while pinned — the pinned panel keeps its content.
    func peek(duration: TimeInterval? = nil) {
        guard !isPinned else { return }
        cancelPeek()
        hoverOpenTask?.cancel()
        state = .open
        updateKeyboardFocus()
        let duration = duration ?? config.peekDurationSeconds
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            if !self.isHovering, !self.shouldResistClose {
                self.state = .closed
                self.updateKeyboardFocus()
            }
        }
    }

    // MARK: - Pinning

    func togglePinned() {
        setPinned(!isPinned)
    }

    func setPinned(_ pinned: Bool, notify: Bool = true) {
        guard pinned != isPinned else { return }
        isPinned = pinned
        temporaryFeatureID = nil
        if pinned {
            requestedFeatureID = NotesStore.featureID
            open()
        } else if !isHovering {
            cancelPeek()
            state = .closed
            updateKeyboardFocus()
        }
        if notify { onPinChanged?(pinned) }
        stateLogger.info("pinned=\(pinned, privacy: .public)")
    }

    // MARK: - Hover

    func handleHover(_ hovering: Bool) {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()
        stateLogger.info("hover=\(hovering, privacy: .public) state=\(String(describing: self.state), privacy: .public)")

        if hovering {
            isHovering = true
            guard state == .closed else { return }
            let delay = config.hoverOpenDelaySeconds
            hoverOpenTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                guard self.isHovering, self.state == .closed else { return }
                self.open()
            }
        } else {
            isHovering = false
            // Small grace period so the notch doesn't collapse on brief exits
            // (e.g. crossing the gap between the notch and a pill).
            hoverCloseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled, let self else { return }
                guard !self.isHovering, !self.shouldResistClose else { return }
                if self.state == .open {
                    self.forceClose()
                }
            }
        }
    }

    func handleTap() {
        if state == .closed { open() }
    }

    // MARK: - Private

    /// Text input needs a key window: only allow it while the Notes panel is
    /// up, so the rest of the time the notch stays fully click-through
    /// keyboard-wise (it never steals focus from real apps).
    private func updateKeyboardFocus() {
        window?.allowsKeyboardFocus = isShowingNotes
    }

    private func cancelPeek() {
        peekTask?.cancel()
        peekTask = nil
    }
}
