import AppKit

/// Gives Ace a life of his own instead of pacing like an avatar.
///
/// Personality: **laid-back and drowsy.** He mostly stands and sits, dozes off,
/// wakes with a stretch, and only occasionally wanders a short distance — and
/// even then he eases in and out rather than gliding at a fixed speed. An
/// "energy" level drifts down as he stays awake and recovers when he sleeps,
/// so his behaviour ebbs and flows rather than firing uniformly at random.
///
/// It also handles grab-and-drop physics and pauses politely while you talk.
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

    /// 0 = exhausted, 1 = wide awake. Drifts with behaviour.
    private var energy: Double = 0.65

    // Walking (eased toward a target instead of constant speed).
    private var walkTargetX: CGFloat = 0
    private var walkStartX: CGFloat = 0

    // Falling.
    private var velocityY: CGFloat = 0

    // Grab.
    private var dragOrigin = CGPoint.zero

    // Blink micro-behaviour.
    private var nextBlinkAt = Date.distantFuture
    private var blinkUntil = Date.distantPast

    // Ambient ad-libs.
    private var nextAmbientAt = Date().addingTimeInterval(20)
    private let stretchLines = ["*yawn*", "*stretch*", "mmh… morning already?", "five more minutes…"]
    private let idleLines = ["so warm…", "hmm…", "…", "*hums quietly*", "just resting my eyes."]

    // Tuning
    private let fps = 60.0
    private var dt: CGFloat { CGFloat(1.0 / fps) }
    private let cruiseSpeed: CGFloat = 34     // points / second (gentle stroll)
    private let rampDistance: CGFloat = 45    // ease-in/out zone
    private let gravity: CGFloat = 1800

    init(window: NSWindow, animator: PetAnimator) {
        self.window = window
        self.animator = animator
    }

    func start() {
        timer?.invalidate()
        placeInitially()
        enterStanding(duration: .random(in: 3...6))
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
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
        guard let window else { return }
        paused = true
        velocityY = 0
        dragOrigin = window.frame.origin
        activity = .grabbed
    }

    func dragBy(_ translation: CGSize) {
        guard let window else { return }
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
            energy = max(0, energy - 0.1)     // a fall is a bit jarring
            enterStanding(duration: .random(in: 2...4))
        } else {
            window.setFrameOrigin(clampX(origin))
        }
    }

    /// Eased walk toward `walkTargetX`: accelerate away from the start, cruise,
    /// decelerate into the target, then rest.
    private func stepWalking() {
        guard let window, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        var origin = window.frame.origin

        let remaining = walkTargetX - origin.x
        if abs(remaining) < 1.5 {
            enterStanding(duration: .random(in: 3...7))   // arrived; take a breather
            return
        }

        let direction: CGFloat = remaining > 0 ? 1 : -1
        let traveled = abs(origin.x - walkStartX)
        let toGo = abs(remaining)
        let ramp = min(min(traveled, toGo) / rampDistance, 1)      // 0…1 ease
        let speed = max(6, cruiseSpeed * ramp)

        origin.x += direction * speed * dt
        origin.y = vf.minY

        // Turn around at the walls.
        if origin.x <= vf.minX { origin.x = vf.minX; enterStanding(duration: .random(in: 2...4)); return }
        let xMax = vf.maxX - window.frame.width
        if origin.x >= xMax { origin.x = xMax; enterStanding(duration: .random(in: 2...4)); return }

        animator.facingLeft = direction < 0
        window.setFrameOrigin(origin)
    }

    // MARK: - Behaviour selection (personality)

    private func chooseNextActivity() {
        // Staying awake slowly tires him out.
        energy = max(0, energy - 0.05)

        if energy < 0.18 {
            // Drowsy: sit, then likely doze off.
            if activity == .sitting && Double.random(in: 0..<1) < 0.7 {
                enterSleeping()
            } else {
                enterSitting()
            }
            return
        }

        // Weighted choice — resting still dominates, but he wanders now and then.
        // Avoid immediately repeating the same restful pose so he doesn't look stuck.
        let r = Double.random(in: 0..<1)
        let walkChance = energy > 0.45 ? 0.38 : 0.20
        if r < walkChance {
            enterWalking()
        } else if activity == .standing {
            enterSitting()
        } else if activity == .sitting {
            enterStanding(duration: .random(in: 3...7))
        } else if r < walkChance + 0.4 {
            enterSitting()
        } else {
            enterStanding(duration: .random(in: 3...7))
        }
    }

    private func enterStanding(duration: TimeInterval) {
        activity = .standing
        activityEndsAt = Date().addingTimeInterval(duration)
        scheduleBlink()
    }

    private func enterSitting() {
        activity = .sitting
        activityEndsAt = Date().addingTimeInterval(.random(in: 6...14))
        energy = max(0, energy - 0.04)
        scheduleBlink()
    }

    private func enterSleeping() {
        activity = .sleeping
        activityEndsAt = Date().addingTimeInterval(.random(in: 15...35))
        nextBlinkAt = .distantFuture      // no blinking while asleep
        // On waking, recover energy and stretch.
        Task { [weak self] in
            let wake = self?.activityEndsAt ?? Date()
            let delay = wake.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, self.activity == .sleeping, !self.paused else { return }
            self.energy = min(1, self.energy + 0.7)
            self.say(self.stretchLines.randomElement() ?? "*yawn*", minGap: 0)
            self.enterStanding(duration: .random(in: 3...6))
        }
    }

    private func enterWalking() {
        guard let window, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let xMax = vf.maxX - window.frame.width
        let here = window.frame.origin.x

        // Short, nearby destination — a stroll, not a march.
        let span = CGFloat.random(in: 70...260) * (Bool.random() ? 1 : -1)
        walkStartX = here
        walkTargetX = min(max(here + span, vf.minX), xMax)
        energy = max(0, energy - 0.12)
        activity = .walking
    }

    private func applyAnimation() {
        if ProcessInfo.processInfo.environment["ACE_DEBUG"] != nil {
            FileHandle.standardError.write(Data("[roam] \(activity) energy=\(String(format: "%.2f", energy))\n".utf8))
        }
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
            if now >= blinkUntil { applyAnimation() }   // restore
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
            say(idleLines.randomElement() ?? "…", minGap: 0)
        }
        nextAmbientAt = Date().addingTimeInterval(.random(in: 25...55))
    }

    private func say(_ line: String, minGap: TimeInterval) {
        onAmbient(line)
    }

    // MARK: - Helpers

    private func snapToFloor() {
        guard let window, let screen = NSScreen.main else { return }
        var origin = window.frame.origin
        origin.y = screen.visibleFrame.minY
        window.setFrameOrigin(clampX(origin))
    }

    /// Start on the floor around the right-center of the screen, not jammed in a
    /// corner.
    private func placeInitially() {
        guard let window, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = vf.minX + (vf.width - window.frame.width) * 0.66
        window.setFrameOrigin(NSPoint(x: x, y: vf.minY))
    }

    private func clampX(_ origin: CGPoint) -> CGPoint {
        guard let window, let screen = NSScreen.main else { return origin }
        let vf = screen.visibleFrame
        var o = origin
        o.x = min(max(o.x, vf.minX), vf.maxX - window.frame.width)
        return o
    }
}
