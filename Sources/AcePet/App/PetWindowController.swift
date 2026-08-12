import AppKit
import SwiftUI

/// Creates and configures the always-on-top, transparent, draggable window that
/// hosts the pet. In Step A this just shows a placeholder; Step B swaps in the
/// animated sprite view and speech bubble.
@MainActor
final class PetWindowController {

    let window: NSWindow

    init() {
        let contentSize = NSSize(width: 220, height: 260)

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Transparent, shadowless, chrome-less floating window.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true      // drag the pet anywhere
        window.ignoresMouseEvents = false

        window.contentView = NSHostingView(rootView: PetView())

        positionBottomRight(size: contentSize)
    }

    /// Place the pet near the bottom-right of the main screen's visible area.
    private func positionBottomRight(size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - size.width - 40,
            y: visible.minY + 40
        )
        window.setFrameOrigin(origin)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
