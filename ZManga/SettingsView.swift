import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    // Reading settings
    @AppStorage("autoLoadNextChapter") var autoLoadNextChapter = true
    @AppStorage("tapToScroll") var tapToScroll = false
    @AppStorage("zoomEnabled") var zoomEnabled = false
    @AppStorage("optimizationEnabled") var optimizationEnabled = false

    // Performance settings (AI-suggested)
    @AppStorage("prefetchEnabled") var prefetchEnabled = false
    @AppStorage("oledDarkMode") var oledDarkMode = false
    @AppStorage("reducedAnimations") var reducedAnimations = false
    @AppStorage("highResCovers") var highResCovers = true
    @AppStorage("aggressiveCaching") var aggressiveCaching = false
    @AppStorage("hapticFeedback") var hapticFeedback = false
    @AppStorage("saveDataMode") var saveDataMode = false
    @AppStorage("keepScreenAwake") var keepScreenAwake = false

    @State private var cacheSizeText = "Calculating..."
    @State private var showCacheClearedAlert = false

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()
                List {

                    // MARK: - Reading Section
                    Section("Reading") {
                        Toggle("Auto-load next chapter", isOn: $autoLoadNextChapter)
                            .tint(ZTheme.accent)
                        Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
                            .tint(ZTheme.accent)
                            .onChange(of: keepScreenAwake) { val in
                                UIApplication.shared.isIdleTimerDisabled = val
                            }
                    }

                    // MARK: - Interaction Section
                    Section {
                        VStack(alignment: .leading, spacing: 0) {
                            Toggle("Tap to Scroll", isOn: $tapToScroll)
                                .tint(ZTheme.accent)
                            if tapToScroll {
                                Text("Single tap scrolls down · Double tap toggles UI")
                                    .font(.system(size: 11))
                                    .foregroundColor(ZTheme.textTertiary)
                                    .padding(.top, 4)
                            }
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Toggle("Zoom", isOn: $zoomEnabled)
                                .tint(ZTheme.accent)
                            if zoomEnabled {
                                Text("Pinch to zoom · Double-tap to reset")
                                    .font(.system(size: 11))
                                    .foregroundColor(ZTheme.textTertiary)
                                    .padding(.top, 4)
                            }
                        }

                        Toggle("Haptic Feedback", isOn: $hapticFeedback)
                            .tint(ZTheme.accent)

                    } header: {
                        Text("Interaction")
                    }

                    // MARK: - Performance Section
                    Section {
                        VStack(alignment: .leading, spacing: 0) {
                            Toggle("Optimization", isOn: $optimizationEnabled)
                                .tint(ZTheme.accent)
                            if optimizationEnabled {
                                Text("Renders only visible pages for lower memory usage")
                                    .font(.system(size: 11))
                                    .foregroundColor(ZTheme.textTertiary)
                                    .padding(.top, 4)
                            }
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Toggle("Page Pre-fetching", isOn: $prefetchEnabled)
                                .tint(ZTheme.accent)
                            if prefetchEnabled {
                                Text("Pre-loads the next 3 pages in background while reading")
                                    .font(.system(size: 11))
                                    .foregroundColor(ZTheme.textTertiary)
                                    .padding(.top, 4)
                            }
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Toggle("Aggressive Caching", isOn: $aggressiveCaching)
                                .tint(ZTheme.accent)
                            if aggressiveCaching {
                                Text("Keeps recently read chapters in memory for instant re-access")
                                    .font(.system(size: 11))
                                    .foregroundColor(ZTheme.textTertiary)
                                    .padding(.top, 4)
                            }
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Toggle("Save Data Mode", isOn: $saveDataMode)
                                .tint(ZTheme.accent)
                            if saveDataMode {
                                Text("Loads lower-quality images to reduce mobile data usage")
                                    .font(.system(size: 11))
                                    .foregroundColor(ZTheme.textTertiary)
                                    .padding(.top, 4)
                            }
                        }

                    } header: {
                        Text("Performance")
                    }

                    // MARK: - Display Section
                    Section {
                        VStack(alignment: .leading, spacing: 0) {
                            Toggle("OLED Dark Mode", isOn: $oledDarkMode)
                                .tint(ZTheme.accent)
                            if oledDarkMode {
                                Text("Uses true black (#000000) backgrounds to save OLED battery")
                                    .font(.system(size: 11))
                                    .foregroundColor(ZTheme.textTertiary)
                                    .padding(.top, 4)
                            }
                        }

                        Toggle("Reduced Animations", isOn: $reducedAnimations)
                            .tint(ZTheme.accent)

                        Toggle("High-Res Covers", isOn: $highResCovers)
                            .tint(ZTheme.accent)

                    } header: {
                        Text("Display")
                    }

                    // MARK: - Storage Section
                    Section("Storage") {
                        HStack {
                            Text("Image Cache")
                            Spacer()
                            Text(cacheSizeText)
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
                            cacheSizeText = "0 KB"
                            showCacheClearedAlert = true
                        }
                        .foregroundColor(ZTheme.danger)

                        Button("Delete All Downloads") {
                            DownloadManager.shared.removeAllDownloads()
                        }
                        .foregroundColor(ZTheme.danger)
                    }

                    // MARK: - About Section
                    Section("About") {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0").foregroundColor(ZTheme.textTertiary)
                        }
                        HStack {
                            Text("Source")
                            Spacer()
                            Text("lek-manga.net").foregroundColor(ZTheme.textTertiary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .background(ZTheme.bg)
                .scrollContentBackground(.hidden)
                .alert("Cache Cleared", isPresented: $showCacheClearedAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Image cache has been cleared successfully.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            cacheSizeText = formatBytes(Int64(URLCache.shared.currentDiskUsage))
        }
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
