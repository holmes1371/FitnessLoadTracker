//
//  CalibrationTests.swift
//  FitnessLoadTrackerTests
//

import Testing
@testable import FitnessLoadTracker

@Suite("Calibration")
struct CalibrationTests {
    @Test("nil suffer score returns nil effort")
    func nilInput() {
        #expect(Calibration.effort(forSufferScore: nil) == nil)
    }

    @Test(
        "bucket boundaries match design/architecture.md table",
        arguments: [
            (0.0, 2.0),
            (29.0, 2.0),
            (30.0, 4.0),
            (59.0, 4.0),
            (60.0, 6.0),
            (119.0, 6.0),
            (120.0, 8.0),
            (199.0, 8.0),
            (200.0, 10.0),
            (350.0, 10.0),
        ]
    )
    func bucket(_ sufferScore: Double, _ expectedEffort: Double) {
        #expect(Calibration.effort(forSufferScore: sufferScore) == expectedEffort)
    }
}
