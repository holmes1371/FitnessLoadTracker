//
//  SyncWindow.swift
//  FitnessLoadTracker
//
//  Pure helper for deciding the `after` Date passed to Strava's
//  list-activities endpoint (#24). Extracted so the window logic is
//  testable without standing up the orchestrator.
//

import Foundation

enum SyncWindow {
    static let defaultOverlap: TimeInterval = 24 * 60 * 60       // 24h — catches Strava-side late posts.
    static let defaultStaleAfter: TimeInterval = 7 * 24 * 60 * 60 // 7d  — checkpoint older than this is treated as nil.
    static let defaultBackfill: TimeInterval = 30 * 24 * 60 * 60  // 30d — fresh install / stale checkpoint window.

    /// Resolves the `after` Date for the next sync.
    /// - Fresh checkpoint: `last − overlap` (overlap absorbs Strava-side
    ///   activities that post hours after they end).
    /// - No checkpoint or stale checkpoint: `now − defaultBackfill`.
    static func resolveAfterDate(
        lastSuccessfulSyncAt: Date?,
        now: Date = Date(),
        overlap: TimeInterval = defaultOverlap,
        staleAfter: TimeInterval = defaultStaleAfter,
        defaultBackfill: TimeInterval = defaultBackfill
    ) -> Date {
        guard let last = lastSuccessfulSyncAt else {
            return now.addingTimeInterval(-defaultBackfill)
        }
        if now.timeIntervalSince(last) > staleAfter {
            return now.addingTimeInterval(-defaultBackfill)
        }
        return last.addingTimeInterval(-overlap)
    }
}
