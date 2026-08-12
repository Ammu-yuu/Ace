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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
