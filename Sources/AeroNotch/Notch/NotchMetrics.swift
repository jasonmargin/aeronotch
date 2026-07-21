import AppKit

/// Screen geometry helpers, replicating TheBoringNotch's closed-notch sizing:
/// physical notch width via the auxiliary areas on either side of it,
/// height from the screen's safe-area insets. Falls back gracefully on
/// notch-less displays (menu-bar height, fixed width).
///
/// `overhang` widens the notch slightly (TheBoringNotch's +4) so the black
/// shape merges seamlessly with the hardware; pass 0 for an exact fit when
/// neighboring content must not be covered.
enum NotchMetrics {
    static func closedNotchSize(for screen: NSScreen?, overhang: CGFloat = 4) -> CGSize {
        var notchWidth: CGFloat = 185
        var notchHeight: CGFloat = 32

        guard let screen else {
            return CGSize(width: notchWidth, height: notchHeight)
        }

        if let topLeft = screen.auxiliaryTopLeftArea?.width,
           let topRight = screen.auxiliaryTopRightArea?.width {
            notchWidth = screen.frame.width - topLeft - topRight + overhang
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
