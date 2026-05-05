import SwiftUI

struct ReaderView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    let manga: Manga
    let chapter: Chapter
    let allChapters: [Chapter]

    @State private var isLoading = true
    @State private var currentPage = 0
    @State private var showUI = true
    @State private var uiTimer: Timer?
    @State private var loadedChapters: [String] = []
    @State private var loadingNextChapter = false
    @State private var allPages: [(chapterSlug: String, url: String)] = []
    @State private var currentChapterSlug: String
    @State private var errorMessage: String?
    @State private var chapterBoundaries: [(slug: String, startIndex: Int)] = []
    @State private var retryCount = 0

    init(manga: Manga, chapter: Chapter, allChapters: [Chapter]) {
        self.manga = manga
        self.chapter = chapter
        self.allChapters = allChapters
        _currentChapterSlug = State(initialValue: chapter.slug)
    }

    var currentChapterNumber: String {
        guard let lastBoundary = chapterBoundaries.last(where: { $0.startIndex <= currentPage }) else {
            return chapter.number
        }
        return manga.chapters.first(where: { $0.slug == lastBoundary.slug })?.number ?? chapter.number
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if isLoading && allPages.isEmpty {
                loadingOverlay
            } else if let err = errorMessage, allPages.isEmpty {
                errorOverlay(err)
            } else if allPages.isEmpty && !isLoading {
                emptyPagesView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(allPages.enumerated()), id: \.offset) { idx, page in
                            if let boundary = chapterBoundaries.first(where: { $0.startIndex == idx }), idx > 0 {
                                ChapterSeparator(number: manga.chapters.first(where: { $0.slug == boundary.slug })?.number ?? "??")
                            }
                            MangaPageImage(url: page.url)
                                .onAppear {
                                    currentPage = idx
                                    saveProgress(pageIndex: idx)
                                    if idx >= allPages.count - 5 && !loadingNextChapter {
                                        Task { await loadNextChapter() }
                                    }
                                }
                        }
                        if loadingNextChapter {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    ProgressView().tint(ZTheme.accent)
                                    Text("جاري تحميل الفصل التالي...")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.5))
                                        .environment(\.layoutDirection, .rightToLeft)
                                }
                                Spacer()
                            }
                            .padding(40)
                        }
                    }
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showUI.toggle() }
                    if showUI { resetUITimer() }
                }
            }

            // زر الإغلاق دائم
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.75))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                            .shadow(color: .black.opacity(0.5), radius: 4)
                    }
                    Spacer()
                }
                .padding(.top, 56)
                .padding(.leading, 16)
                Spacer()
            }

            if showUI { topBar }
            VStack { Spacer(); bottomBar }
        }
        .ignoresSafeArea(edges: .bottom)
        .statusBarHidden(!showUI)
        .task { await loadInitialChapter() }
        .onAppear { resetUITimer() }
    }

    var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(manga.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .environment(\.layoutDirection, .rightToLeft)
                Text("فصل \(currentChapterNumber)")
                    .font(.system(size: 12))
                    .foregroundColor(ZTheme.accent)
            }
            Spacer()
            if !allPages.isEmpty {
                Text("\(currentPage + 1) / \(allPages.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 60)
        .padding(.top, 56)
        .padding(.bottom, 14)
        .background(
            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
        )
        .transition(.opacity)
    }

    var bottomBar: some View {
        Group {
            if !allPages.isEmpty {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.08))
                        Rectangle()
                            .fill(ZTheme.goldGradient)
                            .frame(width: geo.size.width * CGFloat(currentPage + 1) / CGFloat(max(allPages.count, 1)))
                            .animation(.easeOut(duration: 0.15), value: currentPage)
                    }
                }
                .frame(height: 3)
            }
        }
    }

    var loadingOverlay: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(ZTheme.accent)
                .scaleEffect(1.4)
            Text("جاري تحميل الفصل...")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    var emptyPagesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundColor(.white.opacity(0.5))
            Text("لا توجد صفحات")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .environment(\.layoutDirection, .rightToLeft)
            if retryCount < 3 {
                Button("إعادة المحاولة") {
                    retryCount += 1
                    Task { await loadInitialChapter() }
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(ZTheme.bg)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(ZTheme.goldGradient)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Button("رجوع") { dismiss() }
                .foregroundColor(ZTheme.accent)
        }
    }

    func errorOverlay(_ err: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundColor(ZTheme.danger)
            Text(err)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .environment(\.layoutDirection, .rightToLeft)
            Button("إعادة المحاولة") {
                retryCount += 1
                Task { await loadInitialChapter() }
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(ZTheme.bg)
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(ZTheme.goldGradient)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button("رجوع") { dismiss() }
                .foregroundColor(ZTheme.accent)
        }
    }

    // FIX: أولاً تحقق من التحميلات المحلية
    func loadInitialChapter() async {
        isLoading = true
        errorMessage = nil

        // تحقق من الملفات المحملة أولاً
        if let localPages = DownloadManager.shared.getPages(mangaSlug: manga.slug, chapterSlug: chapter.slug) {
            await MainActor.run {
                allPages = localPages.map { (chapterSlug: chapter.slug, url: $0) }
                chapterBoundaries = [(slug: chapter.slug, startIndex: 0)]
                loadedChapters = [chapter.slug]
                isLoading = false
            }
            return
        }

        do {
            let urls = try await MangaService.shared.fetchChapterPages(mangaSlug: manga.slug, chapterSlug: chapter.slug)
            await MainActor.run {
                allPages = urls.map { (chapterSlug: chapter.slug, url: $0) }
                chapterBoundaries = [(slug: chapter.slug, startIndex: 0)]
                loadedChapters = [chapter.slug]
                isLoading = false
            }
        } catch ZMangaError.cloudflareChallenge {
            await MainActor.run {
                errorMessage = "مطلوب تحقق Cloudflare. ارجع وأكمل التحقق."
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func loadNextChapter() async {
        guard let currentBoundary = chapterBoundaries.last else { return }
        let loadedSlugs = Set(loadedChapters)
        guard let currentIdx = allChapters.firstIndex(where: { $0.slug == currentBoundary.slug }),
              currentIdx + 1 < allChapters.count else { return }
        let nextChapter = allChapters[currentIdx + 1]
        guard !loadedSlugs.contains(nextChapter.slug) else { return }

        await MainActor.run { loadingNextChapter = true }
        do {
            // تحقق من الملفات المحملة أولاً
            let urls: [String]
            if let local = DownloadManager.shared.getPages(mangaSlug: manga.slug, chapterSlug: nextChapter.slug) {
                urls = local
            } else {
                urls = try await MangaService.shared.fetchChapterPages(
                    mangaSlug: manga.slug, chapterSlug: nextChapter.slug
                )
            }
            await MainActor.run {
                let startIndex = allPages.count
                allPages.append(contentsOf: urls.map { (chapterSlug: nextChapter.slug, url: $0) })
                chapterBoundaries.append((slug: nextChapter.slug, startIndex: startIndex))
                loadedChapters.append(nextChapter.slug)
                loadingNextChapter = false
            }
        } catch {
            await MainActor.run { loadingNextChapter = false }
        }
    }

    func saveProgress(pageIndex: Int) {
        let chapterSlug: String = {
            for b in chapterBoundaries.reversed() {
                if pageIndex >= b.startIndex { return b.slug }
            }
            return chapter.slug
        }()
        let chapterNum = manga.chapters.first(where: { $0.slug == chapterSlug })?.number ?? chapter.number
        let localPageIndex = pageIndex - (chapterBoundaries.first(where: { $0.slug == chapterSlug })?.startIndex ?? 0)
        let progress = ReadingProgress(
            mangaSlug: manga.slug, mangaTitle: manga.title, mangaCover: manga.coverURL,
            chapterSlug: chapterSlug, chapterNumber: chapterNum, pageIndex: localPageIndex
        )
        store.saveProgress(progress)
    }

    func resetUITimer() {
        uiTimer?.invalidate()
        uiTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.3)) { showUI = false }
        }
    }
}

// MARK: - Manga Page Image
struct MangaPageImage: View {
    let url: String

    var body: some View {
        Group {
            if url.hasPrefix("/") || url.hasPrefix("file://") {
                // ملف محلي
                if let uiImage = UIImage(contentsOfFile: url) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } else {
                    Color.black.frame(height: 200)
                }
            } else {
                CachedAsyncImage(url: URL(string: url))
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.black)
    }
}

// MARK: - Chapter Separator
struct ChapterSeparator: View {
    let number: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            Text("فصل \(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(ZTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(ZTheme.accent.opacity(0.1))
                .overlay(
                    Capsule().stroke(ZTheme.accent.opacity(0.4), lineWidth: 1)
                )
                .clipShape(Capsule())
                .environment(\.layoutDirection, .rightToLeft)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(Color.black)
    }
}