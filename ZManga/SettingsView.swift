import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("autoLoadNextChapter") var autoLoadNextChapter = true
    @AppStorage("tapToScroll") var tapToScroll = true
    @AppStorage("doubleTapUIToggle") var doubleTapUIToggle = true
    @AppStorage("enablePinchZoom") var enablePinchZoom = true
    @AppStorage("preloadNextChapter") var preloadNextChapter = true
    @AppStorage("highQualityImages") var highQualityImages = true

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()
                List {
                    Section("Reading") {
                        Toggle("Auto-load next chapter", isOn: $autoLoadNextChapter)
                            .tint(ZTheme.accent)
                    }

                    Section("Reader Controls") {
                        Toggle("Tap to Scroll", isOn: $tapToScroll)
                            .tint(ZTheme.accent)
                        Toggle("Double Tap to Toggle UI", isOn: $doubleTapUIToggle)
                            .tint(ZTheme.accent)
                        Toggle("Pinch to Zoom", isOn: $enablePinchZoom)
                            .tint(ZTheme.accent)
                    }

                    Section("Performance") {
                        Toggle("Preload Next Chapter", isOn: $preloadNextChapter)
                            .tint(ZTheme.accent)
                        Toggle("High Quality Images", isOn: $highQualityImages)
                            .tint(ZTheme.accent)
                    }

                    Section("Storage") {
                        HStack {
                            Text("Image Cache")
                            Spacer()
                            Text(formatBytes(Int64(URLCache.shared.currentDiskUsage)))
                                .foregroundColor(ZTheme.textSecondary)
                        }
                        HStack {
                            Text("Downloads")
                            Spacer()
                            Text(formatBytes(DownloadManager.shared.downloadedSize))
                                .foregroundColor(ZTheme.textSecondary)
                        }
                        Button("Clear Image Cache") {
                            URLCache.shared.removeAllCachedResponses()
                            if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                                try? FileManager.default.removeItem(at: cacheDir)
                            }
                        }
                        .foregroundColor(ZTheme.danger)
                        Button("Delete All Downloads") {
                            DownloadManager.shared.removeAllDownloads()
                        }
                        .foregroundColor(ZTheme.danger)
                    }

                    Section("About") {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("2.0").foregroundColor(ZTheme.textTertiary)
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

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}