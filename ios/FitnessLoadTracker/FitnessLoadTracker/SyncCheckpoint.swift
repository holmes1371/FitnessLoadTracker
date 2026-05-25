//
//  SyncCheckpoint.swift
//  FitnessLoadTracker
//
//  Persists the timestamp of the last sync that completed without a fatal
//  error (#24). Distinct from SyncLog: SyncLog records every attempt
//  (success or failure, capped at 10); SyncCheckpoint is the durable
//  watermark used to decide the next sync's fetch window.
//

import Foundation

enum SyncCheckpoint {
    static let storageKey = "dev.holmes.fitnessloadtracker.lastSuccessfulSyncAt"

    static func save(_ date: Date, to defaults: UserDefaults = .standard) {
        defaults.set(date.timeIntervalSince1970, forKey: storageKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> Date? {
        guard defaults.object(forKey: storageKey) != nil else { return nil }
        let interval = defaults.double(forKey: storageKey)
        return Date(timeIntervalSince1970: interval)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
