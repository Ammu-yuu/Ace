import Foundation

/// Every animation clip Ace can play. Two groups:
///
/// - **Voice states** — driven by the talk loop (Step C): idle, listening,
///   thinking, speaking.
/// - **Movement states** — driven by the roaming engine (this step): walk, sit,
///   fall, grabbed.
///
/// A state with no frames in `ace.json` falls back to `idle`.
enum PetState: String, CaseIterable, Sendable {
    case idle
    case listening
    case thinking
    case speaking

    case walk
    case sit
    case sleep
    case blink
    case fall
    case grabbed
}
