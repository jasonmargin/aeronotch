import Cocoa

/// Borderless floating panel pinned to the top-center of the screen.
/// Configuration mirrors TheBoringNotch's window (battle-tested against
/// fullscreen apps, spaces, and the menu bar):
/// floats above the menu bar, joins all spaces, never becomes key/main.
final class NotchWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)

        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]

        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
    }

    /// Text input (the Notes notepad) needs a key window. Off by default so
    /// the notch never steals keyboard focus; NotchViewModel flips this on
    /// only while the Notes panel is up. `.nonactivatingPanel` lets the panel
    /// become key without activating the app.
    var allowsKeyboardFocus = false

    override var canBecomeKey: Bool { allowsKeyboardFocus }
    override var canBecomeMain: Bool { false }
}
