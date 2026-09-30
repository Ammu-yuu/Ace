import AppKit

/// Gives Ace a life of his own instead of pacing like an avatar.
///
/// Personality: **laid-back Shimeji.** He mostly wanders — strolls to a spot,
/// pauses, ambles somewhere else — with the occasional longer sit-down and, when
/// he's run down, a doze that he wakes from with a stretch. He blinks and
/// mutters the odd line so he never looks frozen.
///
/// Position is tracked in an internal float (`posX`/`posY`) and only rounded when
/// we set the window, because macOS snaps window origins to whole points — if we
/// measured travel from the (rounded) window frame, slow easing steps would round
/// away to nothing and he'd never move.
@MainActor
final class RoamController {

    private enum Activity { case standing, walking, sitting, sleeping, falling, grabbed }

    private weak var window: NSWindow?
    private let animator: PetAnimator

    /// Called occasionally with a short, in-character line to show in a bubble.
    var onAmbient: (String) -> Void = { _ in }

    private var activity: Activity = .standing { didSet { applyAnimation() } }
    private var paused = false

    private var timer: Timer?
    private var activityEndsAt = Date.distantPast

    /// Internal source-of-truth position (floats); window is synced from these.
    private var posX: CGFloat = 0
    private var posY: CGFloat = 0

    /// 0 = exhausted, 1 = wide awake.
    private var energy: Double = 0.65

    private var walkTargetX: CGFloat = 0
    private var walkStartX: CGFloat = 0
    private var velocityY: CGFloat = 0
    private var dragAnchor = CGPoint.zero

    private var nextBlinkAt = Date.distantFuture
    private var blinkUntil = Date.distantPast

    private var nextAmbientAt = Date().addingTimeInterval(25)
    private let stretchLines = ["*yawn*", "*stretch*", "mmh… morning already?", "five more minutes…"]
    private let idleLines = ["so warm…", "hmm…", "…", "*hums quietly*", "just resting my eyes."]

    // Tuning
    private let fps = 60.0
    private var dt: CGFloat { CGFloat(1.0 / fps) }
    private let cruiseSpeed: CGFloat = 78     // points / second
    private let minSpeed: CGFloat = 22        // floor so easing never stalls
    private let rampDistance: CGFloat = 40    // ease-in / ease-out zone
    private let gravity: CGFloat = 1800

    init(window: NSWindow, animator: PetAnimator) {
        self.window = window
        self.animator = animator
    }

    func start() {
        timer?.invalidate()
        placeInitially()
        enterStanding(duration: .random(in: 2...4))
        // Added to `.common` run-loop modes so the pet keeps moving smoothly even
        // while a menu is open or the user is scrolling/resizing another window.
        // The timer fires on the main thread, so we run the tick directly (no
        // async hop) for steadier frame timing.
        let t = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Conversation coordination

    func pauseForInteraction() {
        paused = true
        if activity != .grabbed && activity != .falling {
            activity = .standing
        }
    }

    func resumeRoaming() {
        guard paused else { return }
        paused = false
        enterStanding(duration: .random(in: 2...4))
    }

    // MARK: - Drag

    func beginDrag() {
        paused = true
        velocityY = 0
        dragAnchor = CGPoint(x: posX, y: posY)
        activity = .grabbed
    }

    func dragBy(_ translation: CGSize) {
        posX = dragAnchor.x + translation.width
        posY = dragAnchor.y - translation.height     // SwiftUI y is top-left based
        clampToBounds()
        syncWindow()
    }

    func endDrag() {
        velocityY = 0
        activity = .falling
    }

    // MARK: - Tick

    private func tick() {
        switch activity {
        case .grabbed:
            return
        case .falling:
            stepFalling()
            return
        default:
            break
        }

        if paused { return }

        handleBlink()
        handleAmbient()

        if activity == .walking {
            stepWalking()
        } else if Date() >= activityEndsAt {
            chooseNextActivity()
        }
    }

    private func stepFalling() {
        guard let screen = NSScreen.main else { return }
        let floorY = screen.visibleFrame.minY

        velocityY += gravity * dt
        posY -= velocityY * dt

        if posY <= floorY {
            posY = floorY
            syncWindow()
            velocityY = 0
            paused = false
            energy = max(0, energy - 0.1)
            enterStanding(duration: .random(in: 2...4))
        } else {
            syncWindow()
        }
    }

    /// Eased walk toward `walkTargetX`: accelerate away from the start, cruise,
    /// decelerate into the target, then rest.
    private func stepWalking() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame

        let remaining = walkTargetX - posX
        if abs(remaining) < 1.5 {
            enterStanding(duration: .random(in: 1...2.5))
            return
        }

        let direction: CGFloat = remaining > 0 ? 1 : -1
        let traveled = abs(posX - walkStartX)
        let toGo = abs(remaining)
        let ramp = min(min(traveled, toGo) / rampDistance, 1)
        let speed = max(minSpeed, cruiseSpeed * ramp)

        posX += direction * speed * dt
        posY = vf.minY
        animator.facingLeft = direction < 0

        // Reached a wall before the target: pause, then pick a new spot.
        if posX <= floorMinX() { posX = floorMinX(); syncWindow(); enterStanding(duration: .random(in: 1...2)); return }
        if posX >= floorMaxX() { posX = floorMaxX(); syncWindow(); enterStanding(duration: .random(in: 1...2)); return }

        syncWindow()
    }

    // MARK: - Behaviour selection (personality)

    private func chooseNextActivity() {
        energy = max(0, energy - 0.04)

        if energy < 0.15 {
            if activity == .sitting && Double.random(in: 0..<1) < 0.6 {
                enterSleeping()
            } else {
                enterSitting()
            }
            return
        }

        // Wandering is the main thing he does: walk to a new spot, brief pause,
        // walk again — with the occasional longer rest.
        let r = Double.random(in: 0..<1)
        if r < 0.62 {
            enterWalking()
        } else if r < 0.84 {
            enterStanding(duration: .random(in: 1.5...3.5))
        } else {
            enterSitting()
        }
    }

    private func enterStanding(duration: TimeInterval) {
        activity = .standing
        activityEndsAt = Date().addingTimeInterval(duration)
        scheduleBlink()
    }

    private func enterSitting() {
        activity = .sitting
        activityEndsAt = Date().addingTimeInterval(.random(in: 8...16))
        energy = min(1, energy + 0.03)
        scheduleBlink()
    }

    private func enterSleeping() {
        activity = .sleeping
        activityEndsAt = Date().addingTimeInterval(.random(in: 15...35))
        nextBlinkAt = .distantFuture
        Task { [weak self] in
            let delay = (self?.activityEndsAt ?? Date()).timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, self.activity == .sleeping, !self.paused else { return }
            self.energy = min(1, self.energy + 0.7)
            self.onAmbient(self.stretchLines.randomElement() ?? "*yawn*")
            self.enterStanding(duration: .random(in: 2...4))
        }
    }

    private func enterWalking() {
        // Stroll a moderate distance in a direction that has room — moderate hops
        // (not one screen-long march) mean he changes direction often and roams.
        let roomRight = floorMaxX() - posX
        let roomLeft = posX - floorMinX()
        var dir: CGFloat = Bool.random() ? 1 : -1
        if dir > 0 && roomRight < 150 { dir = -1 }
        else if dir < 0 && roomLeft < 150 { dir = 1 }
        let want = CGFloat.random(in: 150...450)
        let dist = min(want, dir > 0 ? roomRight : roomLeft)

        walkStartX = posX
        walkTargetX = posX + dir * max(dist, 0)
        energy = max(0, energy - 0.06)
        activity = .walking
    }

    private func applyAnimation() {
        switch activity {
        case .walking:  animator.state = .walk
        case .standing: animator.state = .idle
        case .sitting:  animator.state = .sit
        case .sleeping: animator.state = .sleep
        case .falling:  animator.state = .fall
        case .grabbed:  animator.state = .grabbed
        }
    }

    // MARK: - Micro-behaviours

    private func scheduleBlink() {
        nextBlinkAt = Date().addingTimeInterval(.random(in: 2.5...6))
    }

    private func handleBlink() {
        guard activity == .standing || activity == .sitting else { return }
        let now = Date()
        if animator.state == .blink {
            if now >= blinkUntil { applyAnimation() }
        } else if now >= nextBlinkAt {
            animator.state = .blink
            blinkUntil = now.addingTimeInterval(0.14)
            scheduleBlink()
        }
    }

    private func handleAmbient() {
        guard activity == .standing || activity == .sitting else { return }
        guard Date() >= nextAmbientAt else { return }
        if Double.random(in: 0..<1) < 0.5 {
            onAmbient(idleLines.randomElement() ?? "…")
        }
        nextAmbientAt = Date().addingTimeInterval(.random(in: 25...55))
    }

    // MARK: - Position helpers

    private func placeInitially() {
        guard let window, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        posX = vf.minX + (vf.width - window.frame.width) * 0.66
        posY = vf.minY
        syncWindow()
    }

    private func syncWindow() {
        guard let window else { return }
        // Snap to whole device pixels (not whole points): crisp on Retina, and
        // smoother than integer-point steps because each step is ~0.5pt on 2x.
        let scale = window.backingScaleFactor
        let snap: (CGFloat) -> CGFloat = { scale > 0 ? ($0 * scale).rounded() / scale : $0.rounded() }
        window.setFrameOrigin(NSPoint(x: snap(posX), y: snap(posY)))
    }

    private func floorMinX() -> CGFloat { NSScreen.main?.visibleFrame.minX ?? 0 }

    private func floorMaxX() -> CGFloat {
        guard let window, let screen = NSScreen.main else { return 0 }
        return screen.visibleFrame.maxX - window.frame.width
    }

    private func clampToBounds() {
        posX = min(max(posX, floorMinX()), floorMaxX())
    }
}
