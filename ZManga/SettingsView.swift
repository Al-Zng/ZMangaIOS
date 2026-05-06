import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var logger: Logger
    @AppStorage("autoLoadNextChapter") var autoLoadNextChapter = true

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()
                List {
                    Section("Reading") {
                        Toggle("Auto-load next chapter", isOn: $autoLoadNextChapter)
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

                    Section("Debug Log") {
                        NavigationLink("View Logs") {
                            DebugLogView()
                                .environmentObject(logger)
                        }
                        Button("Clear Logs") {
                            logger.clear()
                        }
                        .foregroundColor(ZTheme.danger)
                    }

                    Section("About") {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0").foregroundColor(ZTheme.textTertiary)
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

struct DebugLogView: View {
    @EnvironmentObject var logger: Logger

    var body: some View {
        List {
            ForEach(logger.entries.sorted(by: { $0.timestamp > $1.timestamp })) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.category)
                        .font(.caption)
                        .foregroundColor(ZTheme.accent)
                    Text(entry.message)
                        .font(.system(size: 12))
                        .foregroundColor(ZTheme.textPrimary)
                    Text(entry.timestamp.formatted(date: .numeric, time: .standard))
                        .font(.caption2)
                        .foregroundColor(ZTheme.textTertiary)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Logs")
        .background(ZTheme.bg)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Clear") { logger.clear() }
            }
        }
    }
}