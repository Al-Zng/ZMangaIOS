// OfflineMangaDetailView.swift

import SwiftUI

struct OfflineMangaDetailView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var dm = DownloadManager.shared
    let slug: String
    var preloadTitle: String = ""
    var preloadCover: String = ""

    @State private var sortAscending = false

    var manga: Manga {
        if let cached = store.mangaCache[slug] {
            return cached
        } else {
            let chapters = downloadedChapters.map { Chapter(slug: $0.chapterSlug, number: $0.chapterNumber) }
            return Manga(slug: slug, title: preloadTitle, coverURL: preloadCover, chapters: chapters)
        }
    }

    var downloadedChapters: [DownloadManager.DownloadedChapter] {
        dm.downloads.values.filter { $0.mangaSlug == slug }
    }

    var sortedChapters: [DownloadManager.DownloadedChapter] {
        let chaps = downloadedChapters
        let withNumeric = chaps.compactMap { chap -> (Double, DownloadManager.DownloadedChapter)? in
            if let num = Double(chap.chapterNumber) { return (num, chap) }
            return nil
        }
        let sorted = withNumeric.sorted(by: { $0.0 < $1.0 })
        if sortAscending {
            return sorted.map { $0.1 }
        } else {
            return sorted.reversed().map { $0.1 }
        }
    }

    var body: some View {
        ZStack {
            ZTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 16) {
                        CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                            .frame(width: 110, height: 155)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.5), radius: 5, y: 2)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(manga.title)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(ZTheme.textPrimary)
                                .lineLimit(3)

                            if !manga.author.isEmpty {
                                Text(manga.author)
                                    .font(.system(size: 13))
                                    .foregroundColor(ZTheme.textSecondary)
                            }

                            HStack(spacing: 6) {
                                if !manga.status.isEmpty {
                                    StatusBadge(text: manga.status)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(20)

                    Divider().background(ZTheme.border).padding(.vertical, 20)

                    HStack {
                        Text("\(sortedChapters.count) CHAPTERS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ZTheme.textSecondary)
                            .tracking(2)
                        Spacer()
                        Button {
                            withAnimation { sortAscending.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 11))
                                Text(sortAscending ? "Oldest" : "Newest")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(ZTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    LazyVStack(spacing: 0) {
                        ForEach(sortedChapters) { chap in
                            OfflineChapterRow(chapter: chap, manga: manga)
                            Divider().background(ZTheme.border).padding(.leading, 16)
                        }
                    }
                    Color.clear.frame(height: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ZTheme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct OfflineChapterRow: View {
    let chapter: DownloadManager.DownloadedChapter
    let manga: Manga

    var body: some View {
        NavigationLink(destination: ReaderView(
            manga: manga,
            chapter: Chapter(slug: chapter.chapterSlug, number: chapter.chapterNumber),
            allChapters: manga.chapters,
            initialPage: 0,
            preloadedPages: DownloadManager.shared.getPages(mangaSlug: chapter.mangaSlug, chapterSlug: chapter.chapterSlug),
            offlineMode: true
        ).environmentObject(AppStore.currentStore!)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Chapter \(chapter.chapterNumber)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ZTheme.textPrimary)
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(ZTheme.success)
                            .font(.system(size: 12))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ZTheme.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(ZTheme.bg)
        }
    }
}