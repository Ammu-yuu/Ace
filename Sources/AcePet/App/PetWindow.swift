import AppKit

/// A borderless window that can still become key/main — needed so the mic button
/// receives clicks and the app can take keyboard/mic focus. Plain borderless
/// `NSWindow`s return `false` for both by default.
final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
