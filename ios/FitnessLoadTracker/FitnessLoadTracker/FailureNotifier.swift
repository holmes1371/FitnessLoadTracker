//
//  FailureNotifier.swift
//  FitnessLoadTracker
//
//  Local notification after `consecutiveThreshold` consecutive top-level sync
//  failures (#5c). "Top-level" = SyncLogEntry.errorSummary != nil (OAuth /
//  network / etc.). Per-item errors don't count — they're routine outcomes
//  like "no match," not failures of the sync itself.
//
//  Anti-spam: a UserDefaults flag tracks whether we've already notified for
//  the current streak. A subsequent successful sync clears the flag, so a
//  new streak can fire again.
//

import Foundation
import UserNotifications

enum FailureNotifier {
    static let consecutiveThreshold = 3
    static let notifiedFlagKey = "dev.holmes.fitnessloadtracker.failureStreakNotified"
    static let notificationIdentifier = "sync-failure-streak"

    enum Decision: Equatable {
        case fire(latestError: String?)
        case resetStreak
        case noop
    }

    /// Pure function — given a log and the current state of the
    /// notified-for-streak flag, decide what to do. Testable without
    /// touching UNUserNotificationCenter.
    static func decision(
        log: [SyncLogEntry],
        defaults: UserDefaults = .standard
    ) -> Decision {
        let recent = Array(log.prefix(consecutiveThreshold))
        let streakHit = recent.count == consecutiveThreshold
            && recent.allSatisfy { $0.errorSummary != nil }
        let alreadyNotified = defaults.bool(forKey: notifiedFlagKey)

        switch (streakHit, alreadyNotified) {
        case (true, false):
            return .fire(latestError: recent.first?.errorSummary)
        case (false, true):
            return .resetStreak
        default:
            return .noop
        }
    }

    static func evaluate(
        log: [SyncLogEntry],
        defaults: UserDefaults = .standard
    ) async {
        switch decision(log: log, defaults: defaults) {
        case .fire(let latestError):
            await scheduleNotification(latestError: latestError)
            defaults.set(true, forKey: notifiedFlagKey)
        case .resetStreak:
            defaults.set(false, forKey: notifiedFlagKey)
        case .noop:
            break
        }
    }

    /// Idempotent — granting more than once is fine; the system caches the
    /// decision. If the user denies, subsequent `add(_:)` calls silently
    /// no-op and Tom won't see failure notifications until he flips the
    /// per-app toggle in iOS Settings.
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    private static func scheduleNotification(latestError: String?) async {
        let content = UNMutableNotificationContent()
        content.title = "Sync failing"
        var body = "FitnessLoadTracker hasn't synced successfully in \(consecutiveThreshold) attempts."
        if let latestError {
            body += " Latest error: \(latestError)"
        }
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            // iOS doesn't support a true zero-second trigger; 1s is the floor.
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
