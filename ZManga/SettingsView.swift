import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("autoLoadNextChapter") var autoLoadNextChapter = true
    @AppStorage("preloadImagesOnBrowse") var preloadImagesOnBrowse = false

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()
                List {
                    Section("Reading") {
                        Toggle(isOn: $autoLoadNextChapter) {
                            Text("Auto-load next chapter")
                                .foregroundColor(ZTheme.textPrimary)
                        }
                        .tint(ZTheme.accent)
                    }

                    Section("Image Cache") {
                        Button {
                            URLCache.shared.removeAllCachedResponses()
                            // Also clear CachedAsyncImage internal cache
                            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                            if let cacheDir = cacheDir {
                                try? FileManager.default.removeItem(at: cacheDir)
                            }
                        } label: {
                            HStack {
                                Text("Clear Image Cache")
                                    .foregroundColor(ZTheme.danger)
                                Spacer()
                                Image(systemName: "trash")
                                    .foregroundColor(ZTheme.danger)
                            }
                        }
                    }

                    Section("Downloads") {
                        Button {
                            DownloadManager.shared.removeAllDownloads()
                        } label: {
                            HStack {
                                Text("Delete All Downloaded Chapters")
                                    .foregroundColor(ZTheme.danger)
                                Spacer()
                                Image(systemName: "trash")
                                    .foregroundColor(ZTheme.danger)
                            }
                        }
                    }

                    Section("About") {
                        HStack {
                            Text("Version")
                                .foregroundColor(ZTheme.textSecondary)
                            Spacer()
                            Text("1.0")
                                .foregroundColor(ZTheme.textTertiary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .background(ZTheme.bg)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}