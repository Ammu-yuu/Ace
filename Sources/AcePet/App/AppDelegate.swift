import AppKit

/// Owns the top-level application lifecycle and the floating pet window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var petController: PetWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PetWindowController()
        controller.show()
        self.petController = controller

        // Bring ourselves forward once at launch so the pet is visible even
        // though we have no Dock icon.
        NSApp.activate(ignoringOtherApps: true)

        // Handy when tuning a sprite sheet: tells you whether Ace found your art
        // or is showing the placeholder.
        let msg = controller.animator.hasRealSprites
            ? "Ace: loaded sprite sheet from assets/\n"
            : "Ace: no sprite sheet found — using placeholder (see assets/README.md)\n"
        FileHandle.standardError.write(Data(msg.utf8))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
