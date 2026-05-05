import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
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
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(0)

                SearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(1)

                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "books.vertical")
                    }
                    .tag(2)

                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "clock")
                    }
                    .tag(3)
            }
            .accentColor(ZTheme.accent)
        }
        .onAppear {
            AppStore.currentStore = store
        }
        .sheet(isPresented: $store.showCloudflareSheet) {
            CloudflareSheet {
                // User solved challenge
            }
            .environmentObject(store)
        }
    }
}