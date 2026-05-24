//
//  FailureNotifierTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import Testing
@testable import FitnessLoadTracker

@Suite("FailureNotifier")
struct FailureNotifierTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func fail(at offset: TimeInterval = 0) -> SyncLogEntry {
        SyncLogEntry(
            id: UUID(),
            timestamp: Date().addingTimeInterval(offset),
            source: .background,
            activitiesProcessed: 0,
            errorSummary: "OAuth refresh failed",
            perItemErrors: 0
        )
    }

    private func success(at offset: TimeInterval = 0) -> SyncLogEntry {
        SyncLogEntry(
            id: UUID(),
            timestamp: Date().addingTimeInterval(offset),
            source: .background,
            activitiesProcessed: 4,
            errorSummary: nil,
            perItemErrors: 0
        )
    }

    @Test("fewer than threshold entries is noop")
    func fewerEntriesNoop() {
        let defaults = freshDefaults()
        let log = [fail(), fail()]
        #expect(FailureNotifier.decision(log: log, defaults: defaults) == .noop)
    }

    @Test("threshold entries with one success in the window is noop")
    func mixedWindowNoop() {
        let defaults = freshDefaults()
        let log = [fail(), success(), fail()]
        #expect(FailureNotifier.decision(log: log, defaults: defaults) == .noop)
    }

    @Test("three consecutive failures + flag false fires")
    func threeFailsFires() {
        let defaults = freshDefaults()
        let log = [fail(), fail(), fail()]
        let result = FailureNotifier.decision(log: log, defaults: defaults)
        #expect(result == .fire(latestError: "OAuth refresh failed"))
    }

    @Test("three consecutive failures + flag already true is noop (no double-fire)")
    func threeFailsAlreadyNotifiedNoop() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: FailureNotifier.notifiedFlagKey)
        let log = [fail(), fail(), fail()]
        #expect(FailureNotifier.decision(log: log, defaults: defaults) == .noop)
    }

    @Test("streak broken by success + flag true resets")
    func successAfterStreakResets() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: FailureNotifier.notifiedFlagKey)
        let log = [success(), fail(), fail()]
        #expect(FailureNotifier.decision(log: log, defaults: defaults) == .resetStreak)
    }

    @Test("streak broken + flag false is noop (don't write redundantly)")
    func successAndFlagAlreadyFalseNoop() {
        let defaults = freshDefaults()
        let log = [success(), fail(), fail()]
        #expect(FailureNotifier.decision(log: log, defaults: defaults) == .noop)
    }

    @Test("more than threshold consecutive failures still fires once (flag false)")
    func longStreakFiresOnce() {
        let defaults = freshDefaults()
        let log = [fail(), fail(), fail(), fail(), fail()]
        let result = FailureNotifier.decision(log: log, defaults: defaults)
        #expect(result == .fire(latestError: "OAuth refresh failed"))
    }
}
