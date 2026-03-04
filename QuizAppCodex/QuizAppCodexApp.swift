//
//  QuizAppCodexApp.swift
//  QuizAppCodex
//
//  Created by chandara-dgc on 4/3/26.
//

import SwiftUI

@main
struct QuizAppCodexApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
