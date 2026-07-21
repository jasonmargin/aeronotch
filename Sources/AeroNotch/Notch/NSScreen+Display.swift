import AppKit

extension NSScreen {
    /// Stable CoreGraphics display id (public API via `deviceDescription`).
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// 1-based position in `NSScreen.screens` — matches AeroSpace's
    /// `%{monitor-appkit-nsscreen-screens-id}`.
    var appKitScreenIndex: Int? {
        guard let displayID else { return nil }
        return NSScreen.screens.firstIndex { $0.displayID == displayID }.map { $0 + 1 }
    }

    /// The screen currently containing the mouse cursor.
    static var screenWithMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }
}
