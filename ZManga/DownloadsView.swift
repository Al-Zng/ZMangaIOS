// DownloadsView.swift

import SwiftUI

// MARK: - كائن مساعد للتنقل (يدعم Identifiable)
struct DownloadedChapterSelection: Identifiable {
    let id = UUID()
    let manga: Manga
    let chapter: Chapter
    let pages: [String]
}

struct DownloadsView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var dm = DownloadManager.shared

    var groupedMangas: [(slug: String, title: String, cover: String, chapters: [DownloadManager.DownloadedChapter])] {
        let dict = Dictionary(grouping: dm.downloads.values, by: { $0.mangaSlug })
        return dict.map { key, value in
            (slug: key, title: value.first?.mangaTitle ?? "", cover: value.first?.mangaCover ?? "", chapters: value)
        }
    }

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
                        if !groupedMangas.isEmpty {
                            Section("Completed") {
                                ForEach(groupedMangas, id: \.slug) { item in
                                    NavigationLink(destination: OfflineMangaDetailView(slug: item.slug, preloadTitle: item.title, preloadCover: item.cover)) {
                                        MangaDownloadCard(title: item.title, cover: item.cover, chapterCount: item.chapters.count)
                                    }
                                }
                                .onDelete { indexSet in
                                    for idx in indexSet {
                                        let slug = groupedMangas[idx].slug
                                        for chapter in dm.downloads.values where chapter.mangaSlug == slug {
                                            dm.deleteChapter(mangaSlug: chapter.mangaSlug, chapterSlug: chapter.chapterSlug)
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

struct MangaDownloadCard: View {
    let title: String
    let cover: String
    let chapterCount: Int

    var body: some View {
        HStack(spacing: 12) {
            if !cover.isEmpty {
                CachedAsyncImage(url: URL(string: cover))
                    .frame(width: 50, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(ZTheme.card).frame(width: 50, height: 70)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ZTheme.textPrimary)
                    .lineLimit(2)
                Text("\(chapterCount) chapter\(chapterCount > 1 ? "s" : "") downloaded")
                    .font(.system(size: 12))
                    .foregroundColor(ZTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(ZTheme.textTertiary)
        }
        .padding(.vertical, 4)
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