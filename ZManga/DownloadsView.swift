import SwiftUI

// MARK: - Offline Manga Detail (shows only downloaded chapters)
struct OfflineMangaDetailView: View {
    @EnvironmentObject var store: AppStore
    let mangaSlug: String
    let mangaTitle: String
    let mangaCover: String

    @StateObject private var dm = DownloadManager.shared
    @State private var selectedChapter: OfflineChapterSelection? = nil

    struct OfflineChapterSelection: Identifiable {
        let id = UUID()
        let manga: Manga
        let chapter: Chapter
        let allChapters: [Chapter]
        let pages: [String]
    }

    var downloadedChapters: [DownloadManager.DownloadedChapter] {
        dm.downloads.values
            .filter { $0.mangaSlug == mangaSlug }
            .sorted { lhs, rhs in
                let l = Double(lhs.chapterNumber) ?? 0
                let r = Double(rhs.chapterNumber) ?? 0
                return l < r
            }
    }

    var body: some View {
        ZStack {
            ZTheme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    // Cover header
                    ZStack(alignment: .bottom) {
                        CachedAsyncImage(url: URL(string: mangaCover))
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                            .clipped()
                        LinearGradient(
                            colors: [.clear, ZTheme.bg],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 140)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mangaTitle)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(ZTheme.textPrimary)
                                .lineLimit(2)
                            Text("\(downloadedChapters.count) chapter\(downloadedChapters.count == 1 ? "" : "s") downloaded")
                                .font(.system(size: 13))
                                .foregroundColor(ZTheme.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider().background(ZTheme.border).padding(.horizontal, 16)

                    LazyVStack(spacing: 0) {
                        ForEach(downloadedChapters) { dc in
                            Button {
                                openChapter(dc)
                            } label: {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Chapter \(dc.chapterNumber)")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(ZTheme.textPrimary)
                                        Text("Downloaded \(dc.downloadedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.system(size: 12))
                                            .foregroundColor(ZTheme.textTertiary)
                                        Text("\(dc.pages.count) pages")
                                            .font(.system(size: 11))
                                            .foregroundColor(ZTheme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill")
                                        .foregroundColor(ZTheme.accent)
                                        .font(.system(size: 13))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            Divider().background(ZTheme.border).padding(.leading, 16)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle("Offline")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedChapter) { sel in
            ReaderView(
                manga: sel.manga,
                chapter: sel.chapter,
                allChapters: sel.allChapters,
                initialPage: 0,
                preloadedPages: sel.pages
            )
            .environmentObject(store)
        }
    }

    private func openChapter(_ dc: DownloadManager.DownloadedChapter) {
        guard let pages = dm.getPages(mangaSlug: dc.mangaSlug, chapterSlug: dc.chapterSlug) else { return }
        let manga = Manga(slug: dc.mangaSlug, title: dc.mangaTitle, coverURL: dc.mangaCover)
        let allDownloadedChapters = downloadedChapters.map { d in
            Chapter(
                slug: d.chapterSlug,
                number: d.chapterNumber,
                pages: dm.getPages(mangaSlug: d.mangaSlug, chapterSlug: d.chapterSlug) ?? []
            )
        }
        let thisChapter = Chapter(slug: dc.chapterSlug, number: dc.chapterNumber, pages: pages)
        selectedChapter = OfflineChapterSelection(
            manga: manga,
            chapter: thisChapter,
            allChapters: allDownloadedChapters,
            pages: pages
        )
    }
}

// MARK: - Downloads View (manga-title grouped)
struct DownloadsView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var dm = DownloadManager.shared

    // Group completed downloads by manga slug
    var groupedDownloads: [(slug: String, title: String, cover: String, chapters: [DownloadManager.DownloadedChapter])] {
        var dict: [String: [DownloadManager.DownloadedChapter]] = [:]
        for chapter in dm.downloads.values {
            dict[chapter.mangaSlug, default: []].append(chapter)
        }
        return dict.map { slug, chapters in
            let sorted = chapters.sorted {
                (Double($0.chapterNumber) ?? 0) < (Double($1.chapterNumber) ?? 0)
            }
            return (
                slug: slug,
                title: chapters.first?.mangaTitle ?? slug,
                cover: chapters.first?.mangaCover ?? "",
                chapters: sorted
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()

                if dm.downloads.isEmpty && dm.activeDownloads.isEmpty && dm.downloadQueue.isEmpty {
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
                        // Active downloads / queue
                        if !dm.activeDownloads.isEmpty || !dm.downloadQueue.isEmpty {
                            Section("Downloading") {
                                ForEach(Array(dm.activeDownloads.keys), id: \.self) { key in
                                    if let chapter = dm.downloads[key] ?? dm.activeChapterMeta(key) {
                                        DownloadingRow(key: key, chapter: chapter,
                                                       progress: dm.activeDownloads[key] ?? 0)
                                    }
                                }
                                ForEach(dm.downloadQueue, id: \.self) { key in
                                    if let chapter = dm.activeChapterMeta(key) {
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
                                                Text("Queued")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(ZTheme.textTertiary)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }

                        // Completed manga groups
                        if !groupedDownloads.isEmpty {
                            Section("Downloaded Manga") {
                                ForEach(groupedDownloads, id: \.slug) { group in
                                    NavigationLink(destination:
                                        OfflineMangaDetailView(
                                            mangaSlug: group.slug,
                                            mangaTitle: group.title,
                                            mangaCover: group.cover
                                        )
                                        .environmentObject(store)
                                    ) {
                                        DownloadedMangaRow(
                                            title: group.title,
                                            cover: group.cover,
                                            chapterCount: group.chapters.count,
                                            latestChapter: group.chapters.last?.chapterNumber ?? ""
                                        )
                                    }
                                }
                                .onDelete { indexSet in
                                    for idx in indexSet {
                                        let group = groupedDownloads[idx]
                                        for ch in group.chapters {
                                            dm.deleteChapter(mangaSlug: ch.mangaSlug, chapterSlug: ch.chapterSlug)
                                        }
                                    }
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
        }
    }
}

// MARK: - Row: Downloaded Manga Title Card
struct DownloadedMangaRow: View {
    let title: String
    let cover: String
    let chapterCount: Int
    let latestChapter: String

    var body: some View {
        HStack(spacing: 12) {
            if !cover.isEmpty {
                CachedAsyncImage(url: URL(string: cover))
                    .frame(width: 50, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(ZTheme.card).frame(width: 50, height: 70)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ZTheme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(ZTheme.accent)
                    Text("\(chapterCount) chapter\(chapterCount == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundColor(ZTheme.textSecondary)
                }
                if !latestChapter.isEmpty {
                    Text("Up to Ch. \(latestChapter)")
                        .font(.system(size: 11))
                        .foregroundColor(ZTheme.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Extension: DownloadManager queue helpers
extension DownloadManager {
    func activeChapterMeta(_ key: String) -> DownloadedChapter? {
        let parts = key.components(separatedBy: "_")
        guard parts.count >= 2 else { return nil }
        let mangaSlug = parts[0]
        let chapterSlug = parts.dropFirst().joined(separator: "_")
        return DownloadedChapter(
            mangaSlug: mangaSlug,
            chapterSlug: chapterSlug,
            chapterNumber: "?",
            mangaTitle: "Loading...",
            mangaCover: "",
            pages: [],
            downloadedAt: Date()
        )
    }
}

// MARK: - Downloading Row (unchanged)
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
