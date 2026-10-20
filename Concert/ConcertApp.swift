//
//  ConcertApp.swift
//  Concert
//
//  Created by Zero Unity on 10/20/26.
//

import SwiftUI

@main
struct ConcertApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
