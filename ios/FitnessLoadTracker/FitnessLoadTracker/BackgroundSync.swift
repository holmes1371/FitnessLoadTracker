//
//  BackgroundSync.swift
//  FitnessLoadTracker
//
//  Wraps BGTaskScheduler so the sync runs without Tom opening the app (#5).
//  iOS-controlled cadence: we ask for "no sooner than 1 hour from now" and
//  iOS picks the actual fire time based on usage/battery/network heuristics.
//

import BackgroundTasks
import Foundation
import UIKit

enum BackgroundSync {
    static let taskIdentifier = "dev.holmes.fitnessloadtracker.sync"
    static let earliestInterval: TimeInterval = 60 * 60  // 1 hour

    /// Diagnostic surface for the debug readout — captures the last submit
    /// error so the UI can show why scheduling failed. Removed when the
    /// debug readout itself goes away in #5b.
    static var lastError: String?

    /// Register the handler. Must be called during app launch (App.init) so
    /// the handler is in place before iOS can ever invoke a queued task.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Submit a fresh refresh request. Idempotent — submitting again replaces
    /// the pending request with the new earliestBeginDate. Safe to call after
    /// every foreground sync and after the BG task itself runs.
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            lastError = nil
        } catch {
            let ns = error as NSError
            lastError = "\(ns.domain) \(ns.code) — \(ns.localizedDescription)"
        }
    }

    @MainActor
    private static func handle(_ task: BGAppRefreshTask) {
        // Re-arm first so a slow sync that hits the expiration handler still
        // leaves a next task pending.
        scheduleNext()

        // HealthKit is encrypted at rest and unreadable while the device is
        // locked. A BG refresh can fire on a locked device; if it does, every
        // HK read/write throws "Protected health data is inaccessible" (#35).
        // Bail cleanly: don't hit Strava for results we can't write, don't log
        // a noisy failure row, and — critically — don't let the run advance
        // SyncCheckpoint past activities we never processed. iOS keeps firing;
        // the work lands on the next fire that happens while unlocked.
        guard UIApplication.shared.isProtectedDataAvailable else {
            task.setTaskCompleted(success: true)
            return
        }

        let healthKit = HealthKitManager()
        let sync = SyncOrchestrator()

        let work = Task { @MainActor in
            await sync.syncRecentActivities(source: .background, healthKit: healthKit)
            task.setTaskCompleted(success: sync.errorMessage == nil)
        }

        task.expirationHandler = {
            work.cancel()
        }
    }
}
