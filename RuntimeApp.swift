//
//  RuntimeApp.swift
//  Runtime
//
//  Created by alvin on 7/7/26.
//

import SwiftUI
import SwiftData

@main
struct RuntimeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [RepositorySource.self, LibraryItem.self, HistoryEntry.self, PlaybackEvent.self])
    }
}
