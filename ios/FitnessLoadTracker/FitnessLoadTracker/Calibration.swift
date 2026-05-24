//
//  Calibration.swift
//  FitnessLoadTracker
//
//  Strava `suffer_score` (HR-zone-weighted, uncapped) → Apple
//  `workoutEffortScore` (1–10 RPE) via the v1 bucket table
//  in design/architecture.md. Locked decision: dumb bucketing,
//  no perceived-exertion prompt.
//

import Foundation

enum Calibration {
    static func effort(forSufferScore sufferScore: Double?) -> Double? {
        guard let score = sufferScore else { return nil }
        switch score {
        case ..<30:    return 2
        case ..<60:    return 4
        case ..<120:   return 6
        case ..<200:   return 8
        default:       return 10
        }
    }
}
