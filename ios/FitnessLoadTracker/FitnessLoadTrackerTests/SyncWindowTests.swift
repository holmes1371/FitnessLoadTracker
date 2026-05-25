//
//  SyncWindowTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import Testing
@testable import FitnessLoadTracker

@Suite("SyncWindow")
struct SyncWindowTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    @Test("nil checkpoint → now − defaultBackfill")
    func nilCheckpointFallsBack() {
        let after = SyncWindow.resolveAfterDate(lastSuccessfulSyncAt: nil, now: now)
        #expect(after == now.addingTimeInterval(-SyncWindow.defaultBackfill))
    }

    @Test("fresh checkpoint → last − overlap")
    func freshCheckpointUsesOverlap() {
        let last = now.addingTimeInterval(-2 * day)
        let after = SyncWindow.resolveAfterDate(lastSuccessfulSyncAt: last, now: now)
        #expect(after == last.addingTimeInterval(-SyncWindow.defaultOverlap))
    }

    @Test("stale checkpoint (>7d) → now − defaultBackfill")
    func staleCheckpointFallsBack() {
        let last = now.addingTimeInterval(-10 * day)
        let after = SyncWindow.resolveAfterDate(lastSuccessfulSyncAt: last, now: now)
        #expect(after == now.addingTimeInterval(-SyncWindow.defaultBackfill))
    }

    @Test("checkpoint exactly at stale boundary → still uses overlap")
    func boundaryAtStaleIsFresh() {
        // staleAfter is exclusive: age > staleAfter triggers fallback; age == staleAfter does not.
        let last = now.addingTimeInterval(-SyncWindow.defaultStaleAfter)
        let after = SyncWindow.resolveAfterDate(lastSuccessfulSyncAt: last, now: now)
        #expect(after == last.addingTimeInterval(-SyncWindow.defaultOverlap))
    }

    @Test("checkpoint just past stale boundary → falls back")
    func justPastStaleFallsBack() {
        let last = now.addingTimeInterval(-(SyncWindow.defaultStaleAfter + 1))
        let after = SyncWindow.resolveAfterDate(lastSuccessfulSyncAt: last, now: now)
        #expect(after == now.addingTimeInterval(-SyncWindow.defaultBackfill))
    }

    @Test("custom overlap/stale/backfill are honored")
    func customParameters() {
        let last = now.addingTimeInterval(-3 * day)
        let after = SyncWindow.resolveAfterDate(
            lastSuccessfulSyncAt: last,
            now: now,
            overlap: 2 * 3600,
            staleAfter: 30 * day,
            defaultBackfill: 60 * day
        )
        #expect(after == last.addingTimeInterval(-2 * 3600))
    }
}
