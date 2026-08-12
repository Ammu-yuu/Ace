import Foundation

/// A parsed reminder ready to be scheduled.
struct Reminder: Sendable {
    let body: String
    let fireDate: Date
}

/// Schedules local reminders. Implemented in **Step G** with `UserNotifications`
/// local notifications (and, optionally, EventKit calendar reminders).
protocol ReminderScheduler: AnyObject {
    /// Schedule `reminder` to fire at its `fireDate`. Returns a confirmation
    /// string suitable for showing/speaking back to the user.
    func schedule(_ reminder: Reminder) async throws -> String
}

/// Placeholder that just logs; replaced with real notification scheduling in
/// Step G.
final class PlaceholderReminderScheduler: ReminderScheduler {
    func schedule(_ reminder: Reminder) async throws -> String {
        print("[Reminders placeholder] would fire at \(reminder.fireDate): \(reminder.body)")
        return "(placeholder) I'd remind you at \(reminder.fireDate)."
    }
}
