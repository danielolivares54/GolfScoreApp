//
//  CaddieWatchApp.swift
//  CaddieWatch Watch App
//

import SwiftUI

@main
struct CaddieWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
