//
//  DistanceEnrichmentTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import HealthKit
import Testing
@testable import FitnessLoadTracker

@Suite("DistanceEnrichment.shouldWrite")
struct DistanceEnrichmentTests {
    @Test("indoor cycling without native distance → write")
    func indoorCyclingWrites() {
        #expect(DistanceEnrichment.shouldWrite(
            activityType: .cycling,
            stravaDistanceMeters: 25_000,
            workoutHasNativeDistance: false,
            alreadyWrittenByUs: false
        ))
    }

    @Test("outdoor cycling that already has distance → skip")
    func nativeDistanceSkips() {
        #expect(!DistanceEnrichment.shouldWrite(
            activityType: .cycling,
            stravaDistanceMeters: 25_000,
            workoutHasNativeDistance: true,
            alreadyWrittenByUs: false
        ))
    }

    @Test("already enriched on a prior sync → skip (idempotent)")
    func alreadyWrittenSkips() {
        #expect(!DistanceEnrichment.shouldWrite(
            activityType: .cycling,
            stravaDistanceMeters: 25_000,
            workoutHasNativeDistance: false,
            alreadyWrittenByUs: true
        ))
    }

    @Test("zero Strava distance → skip (nothing to add)")
    func zeroDistanceSkips() {
        #expect(!DistanceEnrichment.shouldWrite(
            activityType: .cycling,
            stravaDistanceMeters: 0,
            workoutHasNativeDistance: false,
            alreadyWrittenByUs: false
        ))
    }

    @Test("non-cycling activity → skip (distance enrichment is cycling-only)")
    func nonCyclingSkips() {
        for type in [HKWorkoutActivityType.running, .walking, .swimming] {
            #expect(!DistanceEnrichment.shouldWrite(
                activityType: type,
                stravaDistanceMeters: 5_000,
                workoutHasNativeDistance: false,
                alreadyWrittenByUs: false
            ))
        }
    }
}
