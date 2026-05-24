//
//  SyncLogTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import Testing
@testable import FitnessLoadTracker

@Suite("SyncLog")
struct SyncLogTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func entry(
        timestamp: Date = Date(),
        source: SyncLogEntry.Source = .foreground,
        activitiesProcessed: Int = 5,
        errorSummary: String? = nil,
        perItemErrors: Int = 0
    ) -> SyncLogEntry {
        SyncLogEntry(
            id: UUID(),
            timestamp: timestamp,
            source: source,
            activitiesProcessed: activitiesProcessed,
            errorSummary: errorSummary,
            perItemErrors: perItemErrors
        )
    }

    @Test("empty defaults returns empty array")
    func emptyDefaults() {
        let defaults = freshDefaults()
        #expect(SyncLog.recent(from: defaults).isEmpty)
    }

    @Test("append + recent round-trips a single entry")
    func roundTripOne() {
        let defaults = freshDefaults()
        let e = entry()
        SyncLog.append(e, to: defaults)
        let result = SyncLog.recent(from: defaults)
        #expect(result.count == 1)
        #expect(result[0] == e)
    }

    @Test("newer entries appear first")
    func newerFirst() {
        let defaults = freshDefaults()
        let first = entry()
        let second = entry()
        SyncLog.append(first, to: defaults)
        SyncLog.append(second, to: defaults)
        let result = SyncLog.recent(from: defaults)
        #expect(result.map(\.id) == [second.id, first.id])
    }

    @Test("trims to maxEntries — oldest dropped")
    func trimsOldest() {
        let defaults = freshDefaults()
        var inserted: [UUID] = []
        for _ in 0..<(SyncLog.maxEntries + 2) {
            let e = entry()
            inserted.append(e.id)
            SyncLog.append(e, to: defaults)
        }
        let result = SyncLog.recent(from: defaults)
        #expect(result.count == SyncLog.maxEntries)
        // The first two inserted (oldest) should have dropped off.
        let resultIDs = Set(result.map(\.id))
        #expect(!resultIDs.contains(inserted[0]))
        #expect(!resultIDs.contains(inserted[1]))
        // The most recent should be at the top.
        #expect(result[0].id == inserted.last)
    }

    @Test("background source survives round-trip")
    func backgroundSourceCodable() {
        let defaults = freshDefaults()
        let e = entry(source: .background)
        SyncLog.append(e, to: defaults)
        let result = SyncLog.recent(from: defaults)
        #expect(result[0].source == .background)
    }

    @Test("error fields survive round-trip")
    func errorFieldsCodable() {
        let defaults = freshDefaults()
        let e = entry(errorSummary: "OAuth failed", perItemErrors: 2)
        SyncLog.append(e, to: defaults)
        let result = SyncLog.recent(from: defaults)
        #expect(result[0].errorSummary == "OAuth failed")
        #expect(result[0].perItemErrors == 2)
    }
}
