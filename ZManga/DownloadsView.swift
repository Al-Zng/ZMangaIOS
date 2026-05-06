import SwiftUI

struct DownloadedChapterSelection: Identifiable {
    let id = UUID()
    let manga: Manga
    let chapter: Chapter
    let pages: [String]
}

struct DownloadsView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var dm = DownloadManager.shared
    @State private var selectedItem: DownloadedChapterSelection? = nil

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()

                if !NetworkMonitor.shared.isConnected {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundColor(ZTheme.textTertiary)
                        Text("No Internet Connection")
                            .font(.system(size: 15))
                            .foregroundColor(ZTheme.textSecondary)
                        Spacer()
                    }
                } else if dm.downloads.isEmpty && dm.activeDownloads.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundColor(ZTheme.textTertiary)
                        Text("No downloads yet")
                            .font(.system(size: 15))
                            .foregroundColor(ZTheme.textSecondary)
                    }
                } else {
                    List {
                        if !dm.activeDownloads.isEmpty {
                            Section("Downloading") {
                                ForEach(Array(dm.activeDownloads.keys), id: \.self) { key in
                                    if let chapter = dm.downloads[key] ?? dm.activeChapterMeta(key) {
                                        DownloadingRow(key: key, chapter: chapter,
                                                       progress: dm.activeDownloads[key] ?? 0)
                                    }
                                }
                            }
                        }
                        Section("Completed") {
                            ForEach(Array(dm.downloads.values)) { chapter in
                                DownloadCompleteRow(chapter: chapter) {
                                    openDownloadedChapter(chapter)
                                }
                            }
                            .onDelete { indexSet in
                                for idx in indexSet {
                                    let ch = Array(dm.downloads.values)[idx]
                                    dm.deleteChapter(mangaSlug: ch.mangaSlug, chapterSlug: ch.chapterSlug)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .background(ZTheme.bg)
                    .scrollContentBackground(.hidden)
                    .toolbar {
                        if !dm.downloads.isEmpty {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Clear All") { dm.removeAllDownloads() }
                                    .foregroundColor(ZTheme.danger)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $selectedItem) { item in
                ReaderView(manga: item.manga, chapter: item.chapter,
                           allChapters: [item.chapter],
                           initialPage: 0, preloadedPages: item.pages)
                    .environmentObject(store)
            }
        }
    }

    private func openDownloadedChapter(_ chapter: DownloadManager.DownloadedChapter) {
        guard let pages = dm.getPages(mangaSlug: chapter.mangaSlug, chapterSlug: chapter.chapterSlug) else { return }
        let manga = Manga(slug: chapter.mangaSlug, title: chapter.mangaTitle, coverURL: chapter.mangaCover)
        let chap = Chapter(slug: chapter.chapterSlug, number: chapter.chapterNumber, pages: pages)
        selectedItem = DownloadedChapterSelection(manga: manga, chapter: chap, pages: pages)
    }
}

extension DownloadManager {
    func activeChapterMeta(_ key: String) -> DownloadedChapter? {
        let parts = key.components(separatedBy: "_")
        guard parts.count == 2 else { return nil }
        return DownloadedChapter(
            mangaSlug: parts[0], chapterSlug: parts[1],
            chapterNumber: "?", mangaTitle: "Loading...",
            mangaCover: "", pages: [], downloadedAt: Date()
        )
    }
}

struct DownloadingRow: View {
    let key: String
    let chapter: DownloadManager.DownloadedChapter
    let progress: Double

    var body: some View {
        HStack(spacing: 12) {
            if !chapter.mangaCover.isEmpty {
                CachedAsyncImage(url: URL(string: chapter.mangaCover))
                    .frame(width: 50, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(ZTheme.card).frame(width: 50, height: 70)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.mangaTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ZTheme.textPrimary)
                    .lineLimit(1)
                Text("Chapter \(chapter.chapterNumber)")
                    .font(.system(size: 12))
                    .foregroundColor(ZTheme.accent)
                ProgressView(value: progress)
                    .tint(ZTheme.accent)
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11))
                    .foregroundColor(ZTheme.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DownloadCompleteRow: View {
    let chapter: DownloadManager.DownloadedChapter
    var action: (() -> Void)? = nil

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 12) {
                if !chapter.mangaCover.isEmpty {
                    CachedAsyncImage(url: URL(string: chapter.mangaCover))
                        .frame(width: 50, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(ZTheme.card).frame(width: 50, height: 70)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.mangaTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ZTheme.textPrimary)
                        .lineLimit(1)
                    Text("Chapter \(chapter.chapterNumber)")
                        .font(.system(size: 12))
                        .foregroundColor(ZTheme.textSecondary)
                    Text("Downloaded \(chapter.downloadedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundColor(ZTheme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(ZTheme.textTertiary)
            }
        }
    }
}