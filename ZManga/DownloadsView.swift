import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var dm = DownloadManager.shared

    var downloadedMangas: [Manga] {
        var dict: [String: Manga] = [:]
        for chapter in dm.downloads.values {
            if dict[chapter.mangaSlug] == nil {
                let m = Manga(slug: chapter.mangaSlug,
                              title: chapter.mangaTitle,
                              coverURL: chapter.mangaCover)
                dict[chapter.mangaSlug] = m
            }
        }
        return Array(dict.values).sorted { $0.title < $1.title }
    }

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()

                if dm.downloads.isEmpty && dm.activeDownloads.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundColor(ZTheme.textTertiary)
                        Text("No downloads yet")
                            .font(.system(size: 15))
                            .foregroundColor(ZTheme.textSecondary)
                    }
                } else {
                    ScrollView {
                        if !dm.activeDownloads.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("DOWNLOADING")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(ZTheme.textSecondary)
                                    .tracking(1.5)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 16)

                                ForEach(Array(dm.activeDownloads.keys), id: \.self) { key in
                                    if let chapter = dm.downloads[key] ?? dm.activeChapterMeta(key) {
                                        DownloadingRow(key: key, chapter: chapter,
                                                       progress: dm.activeDownloads[key] ?? 0)
                                            .padding(.horizontal, 16)
                                    }
                                }
                            }
                        }

                        Text("LIBRARY")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ZTheme.textSecondary)
                            .tracking(1.5)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(downloadedMangas) { manga in
                                NavigationLink(destination: MangaDetailView(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL, downloadedOnly: true)) {
                                    DownloadedMangaCard(manga: manga)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
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
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(ZTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DownloadedMangaCard: View {
    let manga: Manga
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                .aspectRatio(2/3, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            Text(manga.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ZTheme.textPrimary)
                .lineLimit(2)
        }
    }
}