//
//  DistanceEnrichment.swift
//  FitnessLoadTracker
//
//  Pure gate for the indoor-ride distance enrichment (#37). Peloton/indoor
//  rides reach HealthKit without cycling distance (the source app only writes
//  time/calories/HR); Strava carries the equivalent distance. We can't modify
//  the source-app workout, so we author a standalone distanceCycling sample —
//  but only when it's actually needed. Extracted so the decision is unit-
//  testable without an HKHealthStore.
//

import Foundation
import HealthKit

enum DistanceEnrichment {
    /// Whether to author a standalone cycling-distance sample for a matched
    /// workout. True only for a cycling workout that carries no distance of its
    /// own (the indoor/Peloton case — outdoor rides already have GPS distance)
    /// and that we haven't already enriched on a prior sync.
    static func shouldWrite(
        activityType: HKWorkoutActivityType,
        stravaDistanceMeters: Double,
        workoutHasNativeDistance: Bool,
        alreadyWrittenByUs: Bool
    ) -> Bool {
        activityType == .cycling
            && stravaDistanceMeters > 0
            && !workoutHasNativeDistance
            && !alreadyWrittenByUs
    }
}
