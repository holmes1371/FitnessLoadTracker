//
//  SyncCheckpointTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import Testing
@testable import FitnessLoadTracker

@Suite("SyncCheckpoint")
struct SyncCheckpointTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("empty defaults returns nil")
    func emptyDefaultsIsNil() {
        let defaults = freshDefaults()
        #expect(SyncCheckpoint.load(from: defaults) == nil)
    }

    @Test("save + load round-trips a Date")
    func roundTrip() {
        let defaults = freshDefaults()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        SyncCheckpoint.save(when, to: defaults)
        let loaded = SyncCheckpoint.load(from: defaults)
        #expect(loaded == when)
    }

    @Test("save overwrites a prior value")
    func overwrite() {
        let defaults = freshDefaults()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_001_000)
        SyncCheckpoint.save(earlier, to: defaults)
        SyncCheckpoint.save(later, to: defaults)
        #expect(SyncCheckpoint.load(from: defaults) == later)
    }

    @Test("clear removes a stored value")
    func clear() {
        let defaults = freshDefaults()
        SyncCheckpoint.save(Date(), to: defaults)
        SyncCheckpoint.clear(in: defaults)
        #expect(SyncCheckpoint.load(from: defaults) == nil)
    }
}
