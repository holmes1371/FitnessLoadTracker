//
//  SyncLog.swift
//  FitnessLoadTracker
//
//  Persistent record of the last 10 sync attempts (#5b). Both foreground
//  ("Sync now" tap) and background (BG App Refresh fire) syncs write here
//  so Tom can see what's happened even when he wasn't watching.
//

import Foundation

struct SyncLogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let source: Source
    let activitiesProcessed: Int
    let errorSummary: String?
    let perItemErrors: Int
    // First `.error(msg)` status in items, captured at log time. nil when
    // perItemErrors == 0. Lets the UI surface the actual error string on a
    // ⚠ row without an Xcode debug session (#32). Optional so existing
    // persisted entries decode cleanly.
    let firstItemError: String?

    enum Source: String, Codable {
        case foreground
        case background
    }
}

enum SyncLog {
    static let storageKey = "dev.holmes.fitnessloadtracker.syncLog"
    static let maxEntries = 10

    static func append(_ entry: SyncLogEntry, to defaults: UserDefaults = .standard) {
        var entries = recent(from: defaults)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func recent(from defaults: UserDefaults = .standard) -> [SyncLogEntry] {
        guard let data = defaults.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([SyncLogEntry].self, from: data) else {
            return []
        }
        return entries
    }
}
