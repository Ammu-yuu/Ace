import AppKit

// Entry point for the Ace desktop pet.
//
// We run as an "accessory" app: no Dock icon and no global menu bar, just a
// floating character window. This is the classic behaviour for a Shimeji-style
// desktop pet.
//
// Top-level executable code is treated as non-isolated, but AppKit setup and
// our @MainActor AppDelegate must run on the main actor. The process's main
// thread *is* the main actor, so we assert that and do our setup there.

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
