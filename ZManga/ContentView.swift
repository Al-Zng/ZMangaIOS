import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var network = NetworkMonitor.shared
    @State private var selectedTab = 0

    init() {
        AppStore.currentStore = nil
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(ZTheme.surface)
        appearance.shadowColor = UIColor(ZTheme.border)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(0)

                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(1)

                LibraryView()
                    .tabItem { Label("Library", systemImage: "books.vertical") }
                    .tag(2)

                DownloadsView()
                    .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                    .tag(3)

                HistoryView()
                    .tabItem { Label("History", systemImage: "clock") }
                    .tag(4)
            }
            .accentColor(ZTheme.accent)

            if !network.isConnected {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("No Internet Connection")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .padding()
                    .background(Color.black.opacity(0.9))
                    .foregroundColor(.white)
                }
                .transition(.move(edge: .bottom))
                .animation(.default, value: network.isConnected)
            }
        }
        .onAppear {
            AppStore.currentStore = store
        }
        .sheet(isPresented: $store.showCloudflareSheet) {
            CloudflareSheet {}.environmentObject(store)
        }
    }
}