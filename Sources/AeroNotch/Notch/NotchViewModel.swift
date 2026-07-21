import SwiftUI
import Combine

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

    @Published var closedNotchSize: CGSize

    /// Exact (zero-overhang) notch width — used in menuBarLeft mode where the
    /// placeholder must never bleed past the hardware notch's right edge.
    @Published private(set) var exactClosedNotchWidth: CGFloat

    /// Ideal content width reported live by the active feature (sticky across
    /// close/open so re-expanding doesn't jump).
    @Published var openContentWidth: CGFloat?

    /// Presentation mode for the expanded popover.
    var presentationMode: AeroNotchConfig.PresentationMode { config.presentationMode }

    /// Width of the screen this notch lives on (tracked for strip/band sizing).
    private(set) var screenWidth: CGFloat

    /// Panel width when open (notch mode): content-driven with generous side
    /// margins, clamped between a minimum and the configured cap.
    var effectiveOpenWidth: CGFloat {
        let content = openContentWidth ?? (closedNotchSize.width + 120)
        return min(max(content + 64, closedNotchSize.width + 80), config.maxOpenWidth)
    }

    /// Band width in menuBarLeft mode: from the screen's leading edge to the
    /// notch's leading edge — fixed per screen, independent of content.
    var menuBarBandWidth: CGFloat {
        max(200, screenWidth / 2 - exactClosedNotchWidth / 2)
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

    func open() {
        cancelPeek()
        hoverCloseTask?.cancel()
        state = .open
    }

    /// Closes only when the cursor isn't over the notch.
    func close() {
        guard !isHovering else { return }
        forceClose()
    }

    func forceClose() {
        cancelPeek()
        state = .closed
    }

    /// Transient expansion for workspace switches. Restarts its own timer on
    /// repeat calls, so rapid switches keep the notch up continuously.
    func peek(duration: TimeInterval? = nil) {
        cancelPeek()
        hoverOpenTask?.cancel()
        state = .open
        let duration = duration ?? config.peekDurationSeconds
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            if !self.isHovering {
                self.state = .closed
            }
        }
    }

    // MARK: - Hover

    func handleHover(_ hovering: Bool) {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()

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
                guard !self.isHovering else { return }
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

    private func cancelPeek() {
        peekTask?.cancel()
        peekTask = nil
    }
}
