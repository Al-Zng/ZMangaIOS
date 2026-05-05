import SwiftUI

struct MangaDetailView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var downloadManager = DownloadManager.shared
    let slug: String
    var preloadTitle: String = ""
    var preloadCover: String = ""

    @State private var manga: Manga? = nil
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedChapter: Chapter? = nil
    @State private var showReader = false
    @State private var chapterSortAsc = false
    @State private var showChapterError = false
    @State private var downloadingChapter: String? = nil
    @State private var showDownloads = false

    var sortedChapters: [Chapter] {
        guard let m = manga else { return [] }
        return chapterSortAsc
            ? m.chapters.sorted { (Double($0.number) ?? 0) < (Double($1.number) ?? 0) }
            : m.chapters.sorted { (Double($0.number) ?? 0) > (Double($1.number) ?? 0) }
    }

    var body: some View {
        ZStack {
            ZTheme.bg.ignoresSafeArea()

            if isLoading {
                loadingState
            } else if let manga = manga {
                content(manga: manga)
            } else {
                errorState
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ZTheme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if let manga = manga {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            if store.isInLibrary(manga) {
                                store.removeFromLibrary(manga)
                            } else {
                                store.addToLibrary(manga)
                            }
                        } label: {
                            Image(systemName: store.isInLibrary(manga) ? "heart.fill" : "heart")
                                .foregroundColor(store.isInLibrary(manga) ? ZTheme.accent : ZTheme.textSecondary)
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showReader) {
            Group {
                if let chapter = selectedChapter, let manga = manga {
                    ReaderView(manga: manga, chapter: chapter, allChapters: sortedChapters)
                        .environmentObject(store)
                } else {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 44, weight: .ultraLight))
                                .foregroundColor(ZTheme.danger)
                            Text("بيانات الفصل غير مكتملة")
                                .foregroundColor(.white)
                                .environment(\.layoutDirection, .rightToLeft)
                            Button("إغلاق") { showReader = false }
                                .foregroundColor(ZTheme.accent)
                        }
                    }
                }
            }
        }
        .alert("لا يوجد فصول", isPresented: $showChapterError) {
            Button("حسناً", role: .cancel) { }
        } message: {
            Text("هذه المانجا ليس لها فصول متاحة حالياً.")
                .environment(\.layoutDirection, .rightToLeft)
        }
        .task { await loadDetail() }
    }

    var loadingState: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(ZTheme.card)
                    .frame(width: 110, height: 155)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(preloadTitle.isEmpty ? "جاري التحميل..." : preloadTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(ZTheme.textPrimary)
                        .environment(\.layoutDirection, .rightToLeft)
                    RoundedRectangle(cornerRadius: 4).fill(ZTheme.card).frame(height: 12)
                    RoundedRectangle(cornerRadius: 4).fill(ZTheme.card).frame(width: 80, height: 12)
                }
                Spacer()
            }
            .padding(20)
            ProgressView().tint(ZTheme.accent)
            Spacer()
        }
    }

    var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundColor(ZTheme.danger)
            Text(errorMessage ?? "فشل التحميل")
                .foregroundColor(ZTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .environment(\.layoutDirection, .rightToLeft)
            Button("إعادة المحاولة") { Task { await loadDetail() } }
                .foregroundColor(ZTheme.accent)
        }
    }

    func content(manga: Manga) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection(manga: manga)

                Divider().background(ZTheme.border)

                if !manga.description.isEmpty {
                    descriptionSection(manga.description)
                    Divider().background(ZTheme.border)
                }

                chaptersHeader(count: manga.chapters.count)

                LazyVStack(spacing: 0) {
                    ForEach(sortedChapters) { chapter in
                        ChapterRow(
                            chapter: chapter,
                            manga: manga,
                            progress: store.history.first { $0.mangaSlug == manga.slug && $0.chapterSlug == chapter.slug },
                            downloadManager: downloadManager
                        ) {
                            // FIX: استخدام الفصل مباشرة بدون guard غير ضروري
                            selectedChapter = chapter
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                showReader = true
                            }
                        } onDownload: {
                            Task { await downloadChapter(manga: manga, chapter: chapter) }
                        }
                        Divider().background(ZTheme.border)
                    }
                }

                Color.clear.frame(height: 40)
            }
        }
    }

    func heroSection(manga: Manga) -> some View {
        VStack(spacing: 0) {
            // Cover background blur
            ZStack(alignment: .bottom) {
                CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                    .scaledToFill()
                    .frame(height: 220)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [ZTheme.bg.opacity(0.2), ZTheme.bg.opacity(0.7), ZTheme.bg],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blur(radius: 0)

                // Content overlay
                HStack(alignment: .bottom, spacing: 14) {
                    CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                        .frame(width: 110, height: 155)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(ZTheme.accent.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 4)

                    VStack(alignment: .trailing, spacing: 8) {
                        Text(manga.title)
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(ZTheme.textPrimary)
                            .lineLimit(3)
                            .multilineTextAlignment(.trailing)
                            .environment(\.layoutDirection, .rightToLeft)

                        if !manga.author.isEmpty {
                            Text(manga.author)
                                .font(.system(size: 12))
                                .foregroundColor(ZTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        HStack(spacing: 6) {
                            if !manga.rating.isEmpty {
                                HStack(spacing: 3) {
                                    Text(manga.rating)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(ZTheme.accent)
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(ZTheme.accent)
                                }
                            }
                            if !manga.status.isEmpty {
                                StatusBadge(text: manga.status)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        if !manga.genres.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 5) {
                                    ForEach(manga.genres.prefix(4), id: \.self) { genre in
                                        Text(genre)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(ZTheme.accent)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(ZTheme.accentDim)
                                            .overlay(
                                                Capsule()
                                                    .stroke(ZTheme.accent.opacity(0.3), lineWidth: 0.5)
                                            )
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            // Action buttons
            HStack(spacing: 10) {
                if let _ = manga.chapters.first {
                    Button {
                        guard !manga.chapters.isEmpty else {
                            showChapterError = true
                            return
                        }
                        // أول فصل (الأقل رقماً) أو المتابعة
                        let target = manga.chapters.min(by: { (Double($0.number) ?? 0) < (Double($1.number) ?? 0) }) ?? manga.chapters[0]
                        if let progress = store.history.first(where: { $0.mangaSlug == manga.slug }) {
                            // FIX: البحث عن الفصل بالـ slug بشكل أدق
                            let historyChapter = manga.chapters.first(where: { $0.slug == progress.chapterSlug })
                                ?? manga.chapters.first(where: { $0.number == progress.chapterNumber })
                                ?? target
                            selectedChapter = historyChapter
                        } else {
                            selectedChapter = target
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            showReader = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: store.history.first(where: { $0.mangaSlug == manga.slug }) != nil ? "play.fill" : "book.fill")
                                .font(.system(size: 12))
                            Text(store.history.first(where: { $0.mangaSlug == manga.slug }) != nil ? "واصل القراءة" : "ابدأ القراءة")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(ZTheme.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(ZTheme.goldGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        if store.isInLibrary(manga) {
                            store.removeFromLibrary(manga)
                        } else {
                            store.addToLibrary(manga)
                        }
                    } label: {
                        Image(systemName: store.isInLibrary(manga) ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundColor(store.isInLibrary(manga) ? ZTheme.accent : ZTheme.textSecondary)
                            .frame(width: 48, height: 44)
                            .background(ZTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(ZTheme.border, lineWidth: 1)
                            )
                    }
                } else {
                    Text("لا يوجد فصول متاحة")
                        .font(.system(size: 13))
                        .foregroundColor(ZTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Spacer()
                Text("القصة")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(ZTheme.accent)
                    .tracking(0.5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(ZTheme.textSecondary)
                .lineSpacing(5)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    func chaptersHeader(count: Int) -> some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    chapterSortAsc.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: chapterSortAsc ? "arrow.up" : "arrow.down")
                        .font(.system(size: 11))
                    Text(chapterSortAsc ? "الأقدم" : "الأحدث")
                        .font(.system(size: 12))
                }
                .foregroundColor(ZTheme.textSecondary)
            }

            Spacer()

            Text("\(count) فصل")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ZTheme.textPrimary)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ZTheme.surface)
    }

    func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            let m = try await MangaService.shared.fetchDetail(slug: slug)
            await MainActor.run {
                manga = m
                isLoading = false
            }
        } catch ZMangaError.cloudflareChallenge {
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func downloadChapter(manga: Manga, chapter: Chapter) async {
        // جلب الصفحات أولاً ثم التحميل
        do {
            let pages = try await MangaService.shared.fetchChapterPages(mangaSlug: manga.slug, chapterSlug: chapter.slug)
            await DownloadManager.shared.downloadChapter(manga: manga, chapter: chapter, pages: pages)
        } catch {
            print("Download failed: \(error)")
        }
    }
}

// MARK: - Chapter Row (مع زر تحميل)
struct ChapterRow: View {
    let chapter: Chapter
    let manga: Manga
    let progress: ReadingProgress?
    @ObservedObject var downloadManager: DownloadManager
    let action: () -> Void
    let onDownload: () -> Void

    var isRead: Bool { progress != nil }
    var isDownloaded: Bool { downloadManager.isDownloaded(mangaSlug: manga.slug, chapterSlug: chapter.slug) }
    var isDownloading: Bool { downloadManager.isDownloading(mangaSlug: manga.slug, chapterSlug: chapter.slug) }
    var dlProgress: Double { downloadManager.progress(mangaSlug: manga.slug, chapterSlug: chapter.slug) }

    var body: some View {
        HStack(spacing: 0) {
            // Download button
            Button {
                if isDownloaded {
                    downloadManager.deleteChapter(mangaSlug: manga.slug, chapterSlug: chapter.slug)
                } else if !isDownloading {
                    onDownload()
                }
            } label: {
                ZStack {
                    if isDownloading {
                        ZStack {
                            Circle()
                                .stroke(ZTheme.border, lineWidth: 1.5)
                                .frame(width: 28, height: 28)
                            Circle()
                                .trim(from: 0, to: dlProgress)
                                .stroke(ZTheme.accent, lineWidth: 1.5)
                                .frame(width: 28, height: 28)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear, value: dlProgress)
                        }
                    } else if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(ZTheme.accent)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 22))
                            .foregroundColor(ZTheme.textTertiary)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .padding(.leading, 8)

            // Chapter info (clickable)
            Button(action: action) {
                HStack(spacing: 12) {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 6) {
                            if let p = progress {
                                Text("ص.\(p.pageIndex + 1)")
                                    .font(.system(size: 11))
                                    .foregroundColor(ZTheme.accent)
                            }
                            Text("فصل \(chapter.number)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isRead ? ZTheme.textTertiary : ZTheme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        if !chapter.date.isEmpty {
                            Text(chapter.date)
                                .font(.system(size: 11))
                                .foregroundColor(ZTheme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }

                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(ZTheme.accent.opacity(0.5))
                    }

                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ZTheme.textTertiary)
                }
                .padding(.vertical, 14)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .background(ZTheme.bg)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let text: String

    var color: Color {
        text.lowercased().contains("مستمر") || text.lowercased().contains("ongoing")
            ? ZTheme.success
            : ZTheme.textTertiary
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - FlowLayout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineH: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += lineH + spacing
                x = 0
                lineH = 0
            }
            x += size.width + spacing
            lineH = max(lineH, size.height)
            height = y + lineH
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineH: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += lineH + spacing
                x = bounds.minX
                lineH = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineH = max(lineH, size.height)
        }
    }
}