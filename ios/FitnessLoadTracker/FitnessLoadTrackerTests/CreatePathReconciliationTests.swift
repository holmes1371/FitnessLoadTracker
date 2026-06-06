//
//  CreatePathReconciliationTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import HealthKit
import Testing
@testable import FitnessLoadTracker

@Suite("CreatePathReconciliation")
struct CreatePathReconciliationTests {
    private func candidate(
        startOffset: TimeInterval = 0,
        type: HKWorkoutActivityType = .cycling,
        appAuthored: Bool = false,
        proxy: Bool = false,
        stravaId: Int64? = nil
    ) -> ReconcileCandidate {
        ReconcileCandidate(
            startDate: Date.test().addingTimeInterval(startOffset),
            activityType: type,
            isAppAuthored: appAuthored,
            isDistanceProxy: proxy,
            stravaActivityId: stravaId
        )
    }

    // MARK: - B: foreign-twin suppression gate

    @Test("foreign twin within ±60s, duration ignored → suppress (one twin)")
    func foreignTwinWithinTolerance() {
        // The motivating case: WorkOutDoors twin present but rejected by the
        // strict duration test (moving_time vs elapsed_time).
        let twins = CreatePathReconciliation.foreignTwinIndices(
            in: [candidate(startOffset: 30)],
            targetType: .cycling,
            stravaStart: .test()
        )
        #expect(twins == [0])
    }

    @Test("foreign twin start outside ±60s → not a twin")
    func foreignTwinOutsideTolerance() {
        let twins = CreatePathReconciliation.foreignTwinIndices(
            in: [candidate(startOffset: 90)],
            targetType: .cycling,
            stravaStart: .test()
        )
        #expect(twins.isEmpty)
    }

    @Test("two foreign twins within ±60s → both (caller routes to multipleMatches)")
    func twoForeignTwins() {
        let twins = CreatePathReconciliation.foreignTwinIndices(
            in: [candidate(startOffset: 10), candidate(startOffset: -20)],
            targetType: .cycling,
            stravaStart: .test()
        )
        #expect(twins.count == 2)
    }

    @Test("app-authored copy is not a foreign twin")
    func appAuthoredExcludedFromForeign() {
        let twins = CreatePathReconciliation.foreignTwinIndices(
            in: [candidate(startOffset: 0, appAuthored: true, stravaId: 1)],
            targetType: .cycling,
            stravaStart: .test()
        )
        #expect(twins.isEmpty)
    }

    @Test("distance proxy is never a foreign twin")
    func proxyExcludedFromForeign() {
        let twins = CreatePathReconciliation.foreignTwinIndices(
            in: [candidate(startOffset: 0, proxy: true)],
            targetType: .cycling,
            stravaStart: .test()
        )
        #expect(twins.isEmpty)
    }

    @Test("type mismatch is not a foreign twin")
    func typeMismatchExcludedFromForeign() {
        let twins = CreatePathReconciliation.foreignTwinIndices(
            in: [candidate(startOffset: 0, type: .running)],
            targetType: .cycling,
            stravaStart: .test()
        )
        #expect(twins.isEmpty)
    }

    // MARK: - C: app-authored copy identification (the deletion fence)

    @Test("foreign twin + our copy present → heal identifies our copy")
    func healIdentifiesOurCopy() {
        // The duplicate state: a native twin and our app-authored copy of the
        // same ride coexist. C pinpoints our copy for deletion.
        let candidates = [
            candidate(startOffset: 5),                               // foreign twin
            candidate(startOffset: 0, appAuthored: true, stravaId: 42),
        ]
        let index = CreatePathReconciliation.appAuthoredCopyIndex(
            in: candidates, targetType: .cycling, stravaStart: .test(), stravaActivityId: 42
        )
        #expect(index == 1)
    }

    @Test("our copy with no foreign twin → still identified (caller's twin-count gate protects it)")
    func ourCopyWithoutTwinStillIdentified() {
        // appAuthoredCopyIndex only answers "is our copy here?"; contract item 3
        // (a qualifying twin must exist) is enforced by the orchestrator running
        // this only on the single-foreign-twin path. The predicate itself still
        // finds the copy.
        let index = CreatePathReconciliation.appAuthoredCopyIndex(
            in: [candidate(startOffset: 0, appAuthored: true, stravaId: 42)],
            targetType: .cycling, stravaStart: .test(), stravaActivityId: 42
        )
        #expect(index == 0)
    }

    @Test("app-authored copy with a different Strava id → not a deletion target")
    func differentIdNotDeleted() {
        let index = CreatePathReconciliation.appAuthoredCopyIndex(
            in: [candidate(startOffset: 0, appAuthored: true, stravaId: 99)],
            targetType: .cycling, stravaStart: .test(), stravaActivityId: 42
        )
        #expect(index == nil)
    }

    @Test("foreign copy carrying the id is never a deletion target")
    func foreignNeverDeleted() {
        let index = CreatePathReconciliation.appAuthoredCopyIndex(
            in: [candidate(startOffset: 0, appAuthored: false, stravaId: 42)],
            targetType: .cycling, stravaStart: .test(), stravaActivityId: 42
        )
        #expect(index == nil)
    }

    @Test("a distance proxy is never a deletion target (contract item 2)")
    func proxyNeverDeleted() {
        let index = CreatePathReconciliation.appAuthoredCopyIndex(
            in: [candidate(startOffset: 0, appAuthored: true, proxy: true, stravaId: 42)],
            targetType: .cycling, stravaStart: .test(), stravaActivityId: 42
        )
        #expect(index == nil)
    }

    // MARK: - A: grace-period recency gate

    @Test("ride ended within the grace period → defer")
    func recentRideDefers() {
        let end = Date.test()
        #expect(CreatePathReconciliation.shouldDeferAwaitingTwin(
            activityEnd: end,
            now: end.addingTimeInterval(60 * 60),     // 1h later
            gracePeriod: 3 * 60 * 60                   // 3h grace
        ))
    }

    @Test("ride ended past the grace period → create (do not defer)")
    func oldRideCreates() {
        let end = Date.test()
        #expect(!CreatePathReconciliation.shouldDeferAwaitingTwin(
            activityEnd: end,
            now: end.addingTimeInterval(4 * 60 * 60),  // 4h later
            gracePeriod: 3 * 60 * 60                    // 3h grace
        ))
    }

    @Test("exactly at the grace-period boundary → create (strictly-less-than defers)")
    func boundaryCreates() {
        let end = Date.test()
        #expect(!CreatePathReconciliation.shouldDeferAwaitingTwin(
            activityEnd: end,
            now: end.addingTimeInterval(3 * 60 * 60),
            gracePeriod: 3 * 60 * 60
        ))
    }
}

private extension Date {
    static func test() -> Date {
        Date(timeIntervalSince1970: 1_716_220_800)
    }
}
