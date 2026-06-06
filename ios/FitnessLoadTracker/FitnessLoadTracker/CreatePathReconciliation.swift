//
//  CreatePathReconciliation.swift
//  FitnessLoadTracker
//
//  Pure decision gates for the WorkOutDoors/Strava sync-timing race (#43). The
//  hourly background sync can hit the `.noMatch` create path before the source
//  app's HK twin lands, authoring a duplicate; the moving_time/elapsed_time gap
//  then blocks both Matching and #39 from ever reconciling the two copies. These
//  gates sit on the `.noMatch` branch:
//    A — defer creating a recent no-twin ride until the twin has had time to land.
//    B — suppress the create path when a foreign twin is present but was rejected
//        by the strict duration test (start-proximity only).
//    C — identify our own app-authored copy of a ride that already has a native
//        twin, so the heal can delete it (native twin always wins).
//  Operates on plain structs so the logic is unit-testable without HKWorkout —
//  same pattern as Matching / DuplicateDetection / DistanceEnrichment.
//

import Foundation
import HealthKit

struct ReconcileCandidate: Equatable {
    let startDate: Date
    let activityType: HKWorkoutActivityType
    // Authored by this app (HKSource == HKSource.default()). Distinguishes a copy
    // we created on a prior sync from the source app's native twin.
    let isAppAuthored: Bool
    // Our 1s distance-only sibling (#37) — has its own lifecycle, never a twin
    // and never deleted by the heal.
    let isDistanceProxy: Bool
    let stravaActivityId: Int64?
}

enum CreatePathReconciliation {
    // Same ±60s start tolerance Matching uses; B and C deliberately drop the
    // duration test, which is what the strict matcher already failed on.
    static let toleranceSeconds: TimeInterval = 60

    // B — foreign (non-app-authored, non-proxy) twins of the target type whose
    // start is within ±60s of the Strava start, regardless of duration. Catches
    // the twin that is present but was duration-rejected by the strict matcher.
    static func foreignTwinIndices(
        in candidates: [ReconcileCandidate],
        targetType: HKWorkoutActivityType,
        stravaStart: Date
    ) -> [Int] {
        candidates.enumerated().filter { _, c in
            !c.isAppAuthored && !c.isDistanceProxy &&
            c.activityType == targetType &&
            abs(c.startDate.timeIntervalSince(stravaStart)) <= toleranceSeconds
        }.map(\.offset)
    }

    // C — the app-authored copy eligible for deletion by the heal: our app, this
    // exact Strava id, not a proxy, same type, start within ±60s. Contract items
    // 1-3 as a single pure predicate; nil means no qualifying copy, so the heal
    // deletes nothing (protecting a legitimately Strava-only ride we created).
    static func appAuthoredCopyIndex(
        in candidates: [ReconcileCandidate],
        targetType: HKWorkoutActivityType,
        stravaStart: Date,
        stravaActivityId: Int64
    ) -> Int? {
        candidates.firstIndex { c in
            c.isAppAuthored && !c.isDistanceProxy &&
            c.stravaActivityId == stravaActivityId &&
            c.activityType == targetType &&
            abs(c.startDate.timeIntervalSince(stravaStart)) <= toleranceSeconds
        }
    }

    // A — defer creating when the ride ended less than the grace period ago and
    // no HK twin was found, giving the watch→phone sync time to land the twin.
    // The 24h overlap window re-fetches the ride on the next sync. A ride older
    // than the grace period with no twin is treated as genuinely Strava-only and
    // creates normally.
    static func shouldDeferAwaitingTwin(
        activityEnd: Date,
        now: Date,
        gracePeriod: TimeInterval
    ) -> Bool {
        now.timeIntervalSince(activityEnd) < gracePeriod
    }
}
