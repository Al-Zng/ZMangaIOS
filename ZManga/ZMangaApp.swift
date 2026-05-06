import SwiftUI

@main
struct ZMangaApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var logger = Logger.shared   // أضف هذا السطر

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(network)
                .environmentObject(logger)            // حقنه
                .preferredColorScheme(.dark)
        }
    }
}