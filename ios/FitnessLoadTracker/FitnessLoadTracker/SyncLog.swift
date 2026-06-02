//
//  SyncLog.swift
//  FitnessLoadTracker
//
//  Persistent record of the last 10 sync attempts (#5b). Both foreground
//  ("Sync now" tap) and background (BG App Refresh fire) syncs write here
//  so Tom can see what's happened even when he wasn't watching.
//

import Foundation

nonisolated struct SyncLogEntry: Codable, Identifiable, Equatable {
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
    // Per-activity breakdown captured at log time so a Recent syncs row can
    // expand to show *which* activities were touched and what happened to
    // each (#41). Empty for entries logged before #41 — decoded via
    // decodeIfPresent so legacy JSON still loads. The "synced" headline count
    // is derived from this (members with wasWritten), not activitiesProcessed,
    // so a skip-only overlap re-fetch reads as "0 synced".
    let items: [ItemSummary]

    enum Source: String, Codable {
        case foreground
        case background
    }

    init(
        id: UUID,
        timestamp: Date,
        source: Source,
        activitiesProcessed: Int,
        errorSummary: String?,
        perItemErrors: Int,
        firstItemError: String?,
        items: [ItemSummary] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.activitiesProcessed = activitiesProcessed
        self.errorSummary = errorSummary
        self.perItemErrors = perItemErrors
        self.firstItemError = firstItemError
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        source = try c.decode(Source.self, forKey: .source)
        activitiesProcessed = try c.decode(Int.self, forKey: .activitiesProcessed)
        errorSummary = try c.decodeIfPresent(String.self, forKey: .errorSummary)
        perItemErrors = try c.decode(Int.self, forKey: .perItemErrors)
        firstItemError = try c.decodeIfPresent(String.self, forKey: .firstItemError)
        items = try c.decodeIfPresent([ItemSummary].self, forKey: .items) ?? []
    }
}

// Persisted, display-ready snapshot of one synced activity. Decoupled from
// SyncOrchestrator.ItemStatus on purpose: the log format is plain strings +
// a Bool so renaming an in-flight status case can't break decoding of saved
// history. `outcome` is the human-readable label; `wasWritten` flags the
// four write outcomes that count toward the "synced" headline.
nonisolated struct ItemSummary: Codable, Equatable, Identifiable {
    let id: Int64
    let name: String
    let startDate: Date
    let outcome: String
    let wasWritten: Bool
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
