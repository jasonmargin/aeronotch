import AppKit

/// Screen geometry helpers, replicating TheBoringNotch's closed-notch sizing:
/// exact physical notch width via the auxiliary areas on either side of it,
/// height from the screen's safe-area insets. Falls back gracefully on
/// notch-less displays (menu-bar height, fixed width).
enum NotchMetrics {
    static func closedNotchSize(for screen: NSScreen?) -> CGSize {
        var notchWidth: CGFloat = 185
        var notchHeight: CGFloat = 32

        guard let screen else {
            return CGSize(width: notchWidth, height: notchHeight)
        }

        if let topLeft = screen.auxiliaryTopLeftArea?.width,
           let topRight = screen.auxiliaryTopRightArea?.width {
            notchWidth = screen.frame.width - topLeft - topRight + 4
        }

        if screen.safeAreaInsets.top > 0 {
            notchHeight = screen.safeAreaInsets.top
        } else {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            if menuBarHeight > 0 { notchHeight = menuBarHeight }
        }

        return CGSize(width: notchWidth, height: notchHeight)
    }
}
