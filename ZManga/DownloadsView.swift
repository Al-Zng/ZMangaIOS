import SwiftUI

struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject var store: AppStore

    // تجميع التحميلات حسب المانجا
    var groupedDownloads: [(mangaTitle: String, mangaSlug: String, chapters: [DownloadManager.DownloadedChapter])] {
        var dict: [String: [DownloadManager.DownloadedChapter]] = [:]
        for dl in downloadManager.downloads.values {
            dict[dl.mangaSlug, default: []].append(dl)
        }
        return dict.map { slug, chapters in
            let title = chapters.first?.mangaTitle ?? slug
            let sorted = chapters.sorted { (Double($0.chapterNumber) ?? 0) > (Double($1.chapterNumber) ?? 0) }
            return (mangaTitle: title, mangaSlug: slug, chapters: sorted)
        }
        .sorted { $0.mangaTitle < $1.mangaTitle }
    }

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()

                if groupedDownloads.isEmpty {
                    emptyState
                } else {
                    downloadsList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("تحميلاتي")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ZTheme.textPrimary)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            .toolbarBackground(ZTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundColor(ZTheme.textTertiary)
            Text("لا يوجد تحميلات")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ZTheme.textSecondary)
                .environment(\.layoutDirection, .rightToLeft)
            Text("حمّل الفصول من صفحة المانجا\nللقراءة بدون إنترنت")
                .font(.system(size: 13))
                .foregroundColor(ZTheme.textTertiary)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    var downloadsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(groupedDownloads, id: \.mangaSlug) { group in
                    DownloadGroupSection(
                        mangaTitle: group.mangaTitle,
                        mangaSlug: group.mangaSlug,
                        chapters: group.chapters,
                        downloadManager: downloadManager,
                        store: store
                    )
                    Divider().background(ZTheme.border)
                }
            }
        }
    }
}

struct DownloadGroupSection: View {
    let mangaTitle: String
    let mangaSlug: String
    let chapters: [DownloadManager.DownloadedChapter]
    @ObservedObject var downloadManager: DownloadManager
    var store: AppStore
    @State private var isExpanded = true

    var totalSizeMB: String {
        // تقدير حجم التحميل
        let totalPages = chapters.reduce(0) { $0 + $1.pages.count }
        let estimatedMB = Double(totalPages) * 0.3 // ~300KB per page
        return String(format: "%.1f MB", estimatedMB)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Group header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.left")
                        .font(.system(size: 12))
                        .foregroundColor(ZTheme.textTertiary)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(mangaTitle)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ZTheme.textPrimary)
                            .lineLimit(1)
                            .environment(\.layoutDirection, .rightToLeft)
                        Text("\(chapters.count) فصل · \(totalSizeMB)")
                            .font(.system(size: 11))
                            .foregroundColor(ZTheme.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(ZTheme.surface)
            }

            if isExpanded {
                ForEach(chapters) { chapter in
                    DownloadedChapterRow(
                        mangaSlug: mangaSlug,
                        mangaTitle: mangaTitle,
                        chapter: chapter,
                        downloadManager: downloadManager,
                        store: store
                    )
                    Divider().background(ZTheme.border).padding(.leading, 16)
                }
            }
        }
    }
}

struct DownloadedChapterRow: View {
    let mangaSlug: String
    let mangaTitle: String
    let chapter: DownloadManager.DownloadedChapter
    @ObservedObject var downloadManager: DownloadManager
    var store: AppStore
    @State private var showReader = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // Delete button
            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15))
                    .foregroundColor(ZTheme.danger.opacity(0.7))
            }
            .padding(.leading, 16)
            .confirmationDialog("حذف الفصل؟", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("حذف", role: .destructive) {
                    downloadManager.deleteChapter(mangaSlug: mangaSlug, chapterSlug: chapter.chapterSlug)
                }
                Button("إلغاء", role: .cancel) {}
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("فصل \(chapter.chapterNumber)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ZTheme.textPrimary)
                Text("\(chapter.pages.count) صفحة")
                    .font(.system(size: 11))
                    .foregroundColor(ZTheme.textTertiary)
            }

            // Read button
            Button {
                showReader = true
            } label: {
                HStack(spacing: 5) {
                    Text("اقرأ")
                        .font(.system(size: 12, weight: .bold))
                    Image(systemName: "book.fill")
                        .font(.system(size: 11))
                }
                .foregroundColor(ZTheme.bg)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ZTheme.goldGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
        .background(ZTheme.bg)
        .fullScreenCover(isPresented: $showReader) {
            let fakeChapter = Chapter(
                slug: chapter.chapterSlug,
                number: chapter.chapterNumber,
                title: "",
                date: "",
                pages: chapter.pages
            )
            let fakeManga = Manga(
                slug: mangaSlug,
                title: mangaTitle,
                chapters: [fakeChapter]
            )
            ReaderView(manga: fakeManga, chapter: fakeChapter, allChapters: [fakeChapter])
                .environmentObject(store)
        }
    }
}