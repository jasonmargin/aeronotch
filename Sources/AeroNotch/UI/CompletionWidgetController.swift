import AppKit
import SwiftUI

/// Desktop-level widget showing the completion heatmap — sits on the
/// wallpaper behind app windows (all spaces), draggable, never takes focus.
/// Toggled from the menu / settings (`completionWidgetEnabled`).
@MainActor
final class CompletionWidgetController {
    private var window: NSWindow?

    func show(store: NotesStore) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 160),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isMovableByWindowBackground = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: CompletionWidgetView(store: store))
            window.setFrameAutosaveName("CompletionWidget")
            // First launch (no saved frame): park at the bottom-right corner.
            if window.frame.origin == .zero, let screen = NSScreen.main {
                window.setFrameOrigin(NSPoint(
                    x: screen.visibleFrame.maxX - window.frame.width - 20,
                    y: screen.visibleFrame.minY + 20
                ))
            }
            self.window = window
        }
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.close()
        window = nil
    }
}

private struct CompletionWidgetView: View {
    @ObservedObject var store: NotesStore

    private var todayCount: Int {
        store.completionsByDay[ObsidianTodoScanner.todayString()] ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Completed")
                    .font(.notch(size: 11, weight: .semibold))
                Spacer()
                if todayCount > 0 {
                    Text("\(todayCount) today")
                        .font(.notch(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .foregroundStyle(.white.opacity(0.85))
            CompletionHeatmapView(tasksByDay: store.completedTasksByDay, weeks: 10)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.75))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .padding(4)
    }
}
