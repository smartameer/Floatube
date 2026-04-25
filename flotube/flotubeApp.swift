//
//  flotubeApp.swift
//  flotube
//
//  Created by Ameer on 25/04/26.
//

import SwiftUI
import CoreData

@main
struct flotubeApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
