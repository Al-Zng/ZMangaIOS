import SwiftUI

@main
struct ZMangaApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var network = NetworkMonitor.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(network)
                .preferredColorScheme(.dark)
        }
    }
}