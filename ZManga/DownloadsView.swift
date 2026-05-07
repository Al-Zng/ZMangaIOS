// DownloadsView.swift

import SwiftUI

// MARK: - كائن مساعد للتنقل (يدعم Identifiable)
struct DownloadedMangaSelection: Identifiable {
    let id = UUID()
    let mangaSlug: String
    let mangaTitle: String
    let mangaCover: String
}

struct DownloadsView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var dm = DownloadManager.shared
    @State private var selectedManga: DownloadedMangaSelection? = nil

    // تجميع الفصول المحملة حسب المانجا
    var downloadedMangas: [DownloadedMangaGroup] {
        let grouped = Dictionary(grouping: dm.downloads.values) { $0.mangaSlug }
        return grouped.compactMap { slug, chapters -> DownloadedMangaGroup? in
            guard let first = chapters.first else { return nil }
            // إزالة التكرار لنفس المانجا
            let uniqueChapters = Array(Set(chapters)).sorted { (Double($0.chapterNumber) ?? 0) > (Double($1.chapterNumber) ?? 0) }
            return DownloadedMangaGroup(
                mangaSlug: slug,
                mangaTitle: first.mangaTitle,
                mangaCover: first.mangaCover,
                chapters: uniqueChapters
            )
        }.sorted { $0.mangaTitle < $1.mangaTitle }
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
                        Section("Completed") {
                            ForEach(downloadedMangas) { group in
                                NavigationLink(destination: DownloadedMangaDetailView(mangaSlug: group.mangaSlug, mangaTitle: group.mangaTitle, mangaCover: group.mangaCover)) {
                                    DownloadCompleteRow(mangaTitle: group.mangaTitle, mangaCover: group.mangaCover, chapterCount: group.chapters.count)
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

// MARK: - نموذج مجموعة المانجا المحملة
struct DownloadedMangaGroup: Identifiable {
    var id: String { mangaSlug }
    let mangaSlug: String
    let mangaTitle: String
    let mangaCover: String
    let chapters: [DownloadManager.DownloadedChapter]
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
    let mangaTitle: String
    let mangaCover: String
    let chapterCount: Int

    var body: some View {
        HStack(spacing: 12) {
            if !mangaCover.isEmpty {
                CachedAsyncImage(url: URL(string: mangaCover))
                    .frame(width: 50, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(ZTheme.card).frame(width: 50, height: 70)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(mangaTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ZTheme.textPrimary)
                    .lineLimit(1)
                Text("\(chapterCount) chapters downloaded")
                    .font(.system(size: 12))
                    .foregroundColor(ZTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(ZTheme.textTertiary)
        }
    }
}

// MARK: - صفحة تفاصيل المانجا المحملة (فصول محملة فقط)
struct DownloadedMangaDetailView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var dm = DownloadManager.shared
    let mangaSlug: String
    let mangaTitle: String
    let mangaCover: String

    @State private var selectedChapter: Chapter? = nil
    @State private var chapterSortAsc = false

    var downloadedChapters: [DownloadManager.DownloadedChapter] {
        dm.downloads.values.filter { $0.mangaSlug == mangaSlug }
            .sorted { chapterSortAsc ?
                (Double($0.chapterNumber) ?? 0) < (Double($1.chapterNumber) ?? 0) :
                (Double($0.chapterNumber) ?? 0) > (Double($1.chapterNumber) ?? 0)
            }
    }

    var body: some View {
        ZStack {
            ZTheme.bg.ignoresSafeArea()
            
            if downloadedChapters.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundColor(ZTheme.textTertiary)
                    Text("No downloaded chapters")
                        .font(.system(size: 15))
                        .foregroundColor(ZTheme.textSecondary)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header بسيط
                        HStack(alignment: .top, spacing: 16) {
                            CachedAsyncImage(url: URL(string: mangaCover))
                                .frame(width: 110, height: 155)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.5), radius: 5, y: 2)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(mangaTitle)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(ZTheme.textPrimary)
                                    .lineLimit(3)
                                
                                Text("\(downloadedChapters.count) chapters downloaded")
                                    .font(.system(size: 13))
                                    .foregroundColor(ZTheme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(20)
                        
                        Divider().background(ZTheme.border).padding(.vertical, 20)
                        
                        // Chapters header
                        HStack {
                            Text("\(downloadedChapters.count) CHAPTERS")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(ZTheme.textSecondary)
                                .tracking(2)
                            
                            Spacer()
                            
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    chapterSortAsc.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: chapterSortAsc ? "arrow.up" : "arrow.down")
                                        .font(.system(size: 11))
                                    Text(chapterSortAsc ? "Oldest" : "Newest")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(ZTheme.textSecondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        
                        // قائمة الفصول
                        LazyVStack(spacing: 0) {
                            ForEach(downloadedChapters) { downloadedChapter in
                                let chapter = Chapter(slug: downloadedChapter.chapterSlug, number: downloadedChapter.chapterNumber)
                                let progress = store.history.first { $0.mangaSlug == mangaSlug && $0.chapterSlug == downloadedChapter.chapterSlug }
                                let isDownloaded = dm.isDownloaded(mangaSlug: mangaSlug, chapterSlug: downloadedChapter.chapterSlug)
                                let localPages = dm.getPages(mangaSlug: mangaSlug, chapterSlug: downloadedChapter.chapterSlug)
                                
                                Button {
                                    let manga = Manga(slug: mangaSlug, title: mangaTitle, coverURL: mangaCover)
                                    selectedChapter = chapter
                                } label: {
                                    DownloadedChapterRow(
                                        chapterNumber: downloadedChapter.chapterNumber,
                                        isRead: progress != nil
                                    )
                                }
                                Divider().background(ZTheme.border).padding(.leading, 16)
                            }
                        }
                        
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .navigationTitle(mangaTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedChapter) { chapter in
            let manga = Manga(slug: mangaSlug, title: mangaTitle, coverURL: mangaCover)
            let allDownloadedChapters = downloadedChapters.map {
                Chapter(slug: $0.chapterSlug, number: $0.chapterNumber, date: "", pages: $0.pages)
            }
            // ترتيب الفصول حسب الحاجة للـ infinite scroll
            let sortedChapters = chapterSortAsc ?
                allDownloadedChapters.sorted { (Double($0.number) ?? 0) < (Double($1.number) ?? 0) } :
                allDownloadedChapters.sorted { (Double($0.number) ?? 0) > (Double($1.number) ?? 0) }
            
            let progress = store.history.first { $0.mangaSlug == mangaSlug && $0.chapterSlug == chapter.slug }
            
            ReaderView(
                manga: manga,
                chapter: chapter,
                allChapters: sortedChapters,
                initialPage: progress?.pageIndex ?? 0,
                preloadedPages: dm.getPages(mangaSlug: mangaSlug, chapterSlug: chapter.slug),
                isOfflineMode: true
            )
            .environmentObject(store)
        }
    }
}

struct DownloadedChapterRow: View {
    let chapterNumber: String
    let isRead: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Chapter \(chapterNumber)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isRead ? ZTheme.textTertiary : ZTheme.textPrimary)
                    
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
        .contextMenu {
            Button(role: .destructive) {
                // سيتم تمرير الـ delete action من الخارج
            } label: {
                Label("Delete Download", systemImage: "trash")
            }
        }
    }
}