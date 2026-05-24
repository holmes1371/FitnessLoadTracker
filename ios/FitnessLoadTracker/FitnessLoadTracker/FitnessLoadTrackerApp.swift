//
//  FitnessLoadTrackerApp.swift
//  FitnessLoadTracker
//
//  Created by Tom Holmes on 5/24/26.
//

import SwiftUI

@main
struct FitnessLoadTrackerApp: App {
    init() {
        // Register the BG refresh handler synchronously at launch — iOS
        // requires this to happen before applicationDidFinishLaunching returns.
        BackgroundSync.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { BackgroundSync.scheduleNext() }
        }
    }
}
