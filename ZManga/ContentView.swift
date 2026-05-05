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

        // Unselected
        let unselected = UITabBarItemAppearance()
        unselected.normal.iconColor = UIColor(ZTheme.textTertiary)
        unselected.normal.titleTextAttributes = [
            .foregroundColor: UIColor(ZTheme.textTertiary),
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        appearance.stackedLayoutAppearance = unselected

        // Selected
        let selected = UITabBarItemAppearance()
        selected.selected.iconColor = UIColor(ZTheme.accent)
        selected.selected.titleTextAttributes = [
            .foregroundColor: UIColor(ZTheme.accent),
            .font: UIFont.systemFont(ofSize: 10, weight: .bold)
        ]
        appearance.stackedLayoutAppearance = selected

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("الرئيسية", systemImage: selectedTab == 0 ? "house.fill" : "house")
                    }
                    .tag(0)

                SearchView()
                    .tabItem {
                        Label("بحث", systemImage: "magnifyingglass")
                    }
                    .tag(1)

                LibraryView()
                    .tabItem {
                        Label("مكتبتي", systemImage: selectedTab == 2 ? "heart.fill" : "heart")
                    }
                    .tag(2)

                DownloadsView()
                    .tabItem {
                        Label("تحميلاتي", systemImage: selectedTab == 3 ? "arrow.down.circle.fill" : "arrow.down.circle")
                    }
                    .tag(3)

                HistoryView()
                    .tabItem {
                        Label("السجل", systemImage: selectedTab == 4 ? "clock.fill" : "clock")
                    }
                    .tag(4)
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