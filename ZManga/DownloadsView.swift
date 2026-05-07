import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var dm = DownloadManager.shared

    // تجميع المحمّلات حسب المانجا
    var downloadedManga: [Manga] {
        var list: [Manga] = []
        let grouped = Dictionary(grouping: dm.downloads.values, by: { $0.mangaSlug })
        for (slug, chapters) in grouped {
            guard let first = chapters.first else { continue }
            let manga = Manga(
                slug: slug,
                title: first.mangaTitle,
                coverURL: first.mangaCover,
                chapters: chapters.map {
                    Chapter(slug: $0.chapterSlug, number: $0.chapterNumber, date: "", pages: $0.pages)
                }
            )
            list.append(manga)
        }
        return list.sorted { $0.title < $1.title }
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
                                ForEach(dm.queue, id: \.id) { task in
                                    DownloadingRow(
                                        mangaTitle: task.mangaTitle,
                                        chapterNumber: task.chapterNumber,
                                        progress: dm.progress(mangaSlug: task.mangaSlug, chapterSlug: task.chapterSlug)
                                    )
                                }
                            }
                        }
                        Section("Completed") {
                            ForEach(downloadedManga) { manga in
                                NavigationLink(
                                    destination: MangaDetailView(
                                        slug: manga.slug,
                                        preloadTitle: manga.title,
                                        preloadCover: manga.coverURL,
                                        showOnlyDownloaded: true
                                    )
                                ) {
                                    HStack(spacing: 12) {
                                        CachedAsyncImage(url: URL(string: manga.coverURL))
                                            .frame(width: 50, height: 70)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(manga.title)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(ZTheme.textPrimary)
                                                .lineLimit(1)
                                            Text("\(manga.chapters.count) chapters")
                                                .font(.system(size: 12))
                                                .foregroundColor(ZTheme.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(ZTheme.textTertiary)
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                for idx in indexSet {
                                    let manga = downloadedManga[idx]
                                    for chapter in manga.chapters {
                                        dm.deleteChapter(mangaSlug: manga.slug, chapterSlug: chapter.slug)
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

struct DownloadingRow: View {
    let mangaTitle: String
    let chapterNumber: String
    let progress: Double

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(ZTheme.card).frame(width: 50, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text(mangaTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ZTheme.textPrimary)
                    .lineLimit(1)
                Text("Chapter \(chapterNumber)")
                    .font(.system(size: 12))
                    .foregroundColor(ZTheme.accent)
                ProgressView(value: progress)
                    .tint(ZTheme.accent)
                    .scaleEffect(x: 1, y: 2, anchor: .center)
            }
        }
        .padding(.vertical, 4)
    }
}