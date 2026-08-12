import Foundation

/// The animation states the pet can be in. Step B drives only `.idle`; the
/// listening / thinking / speaking states are wired to the voice loop in later
/// steps (C, E, H). Defining them now means the animator and sprite loader are
/// ready and we just flip `animator.state` later.
enum PetState: String, CaseIterable, Sendable {
    case idle
    case listening
    case thinking
    case speaking
}
