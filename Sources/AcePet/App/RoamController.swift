import AppKit

/// Makes Ace roam the screen like it's home: walk along the floor, pause, sit,
/// and — when you grab it — dangle from the cursor and fall back down when let
/// go. Pauses politely while you're talking to it, and resumes afterwards.
///
/// It drives two things every tick: the window's position (physics) and the
/// animator's clip (walk / idle / sit / fall / grabbed).
@MainActor
final class RoamController {

    private enum Activity { case standing, walking, sitting, falling, grabbed }

    private weak var window: NSWindow?
    private let animator: PetAnimator

    private var activity: Activity = .standing {
        didSet { applyAnimation() }
    }

    /// True while a conversation is active — the roaming AI holds still, but
    /// grab/fall physics still run.
    private var paused = false

    private var timer: Timer?
    private var velocityX: CGFloat = 0
    private var velocityY: CGFloat = 0
    private var activityEndsAt = Date.distantPast
    private var dragOrigin = CGPoint.zero

    // Tuning
    private let fps = 60.0
    private var dt: CGFloat { CGFloat(1.0 / fps) }
    private let walkSpeed: CGFloat = 55      // points / second
    private let gravity: CGFloat = 1800      // points / second^2

    init(window: NSWindow, animator: PetAnimator) {
        self.window = window
        self.animator = animator
    }

    func start() {
        timer?.invalidate()
        snapToFloor()
        pickNextActivity()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    // MARK: - Conversation coordination

    func pauseForInteraction() {
        paused = true
        velocityX = 0
        if activity != .grabbed && activity != .falling {
            activity = .standing
        }
    }

    func resumeRoaming() {
        guard paused else { return }
        paused = false
        pickNextActivity()
    }

    // MARK: - Drag (from the view's gesture)

    func beginDrag() {
        guard let window else { return }
        paused = true
        velocityX = 0
        velocityY = 0
        dragOrigin = window.frame.origin
        activity = .grabbed
    }

    func dragBy(_ translation: CGSize) {
        guard let window else { return }
        // SwiftUI translation is top-left based; window Y is bottom-left based.
        var origin = dragOrigin
        origin.x += translation.width
        origin.y -= translation.height
        window.setFrameOrigin(clampX(origin))
    }

    func endDrag() {
        velocityY = 0
        activity = .falling
    }

    // MARK: - Tick

    private func tick() {
        switch activity {
        case .grabbed:
            return                    // position owned by the drag gesture
        case .falling:
            stepFalling()
            return
        default:
            break
        }

        if paused { return }          // conversation in progress: hold still
        stepRoaming()
    }

    private func stepFalling() {
        guard let window, let screen = NSScreen.main else { return }
        let floorY = screen.visibleFrame.minY

        velocityY += gravity * dt
        var origin = window.frame.origin
        origin.y -= velocityY * dt

        if origin.y <= floorY {
            origin.y = floorY
            window.setFrameOrigin(clampX(origin))
            velocityY = 0
            paused = false
            pickNextActivity()        // land and carry on
        } else {
            window.setFrameOrigin(clampX(origin))
        }
    }

    private func stepRoaming() {
        guard let window, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let xMax = vf.maxX - window.frame.width

        if activity == .walking {
            var origin = window.frame.origin
            origin.x += velocityX * dt
            origin.y = vf.minY

            if origin.x <= vf.minX {
                origin.x = vf.minX
                velocityX = abs(velocityX)
                animator.facingLeft = false
            } else if origin.x >= xMax {
                origin.x = xMax
                velocityX = -abs(velocityX)
                animator.facingLeft = true
            }
            window.setFrameOrigin(origin)
        }

        if Date() >= activityEndsAt {
            pickNextActivity()
        }
    }

    // MARK: - Behavior selection

    private func pickNextActivity() {
        snapToFloor()

        switch Double.random(in: 0..<1) {
        case ..<0.55:
            let dir: CGFloat = Bool.random() ? 1 : -1
            velocityX = walkSpeed * dir
            animator.facingLeft = dir < 0
            activity = .walking
            activityEndsAt = Date().addingTimeInterval(.random(in: 2...5))
        case ..<0.80:
            velocityX = 0
            activity = .standing
            activityEndsAt = Date().addingTimeInterval(.random(in: 1...3))
        default:
            velocityX = 0
            activity = .sitting
            activityEndsAt = Date().addingTimeInterval(.random(in: 2...4))
        }
    }

    private func applyAnimation() {
        switch activity {
        case .walking:  animator.state = .walk
        case .standing: animator.state = .idle
        case .sitting:  animator.state = .sit
        case .falling:  animator.state = .fall
        case .grabbed:  animator.state = .grabbed
        }
    }

    // MARK: - Helpers

    private func snapToFloor() {
        guard let window, let screen = NSScreen.main else { return }
        var origin = window.frame.origin
        origin.y = screen.visibleFrame.minY
        window.setFrameOrigin(clampX(origin))
    }

    private func clampX(_ origin: CGPoint) -> CGPoint {
        guard let window, let screen = NSScreen.main else { return origin }
        let vf = screen.visibleFrame
        var o = origin
        o.x = min(max(o.x, vf.minX), vf.maxX - window.frame.width)
        return o
    }
}
