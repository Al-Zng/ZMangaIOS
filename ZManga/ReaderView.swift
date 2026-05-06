import SwiftUI

struct ReaderView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    let manga: Manga
    let chapter: Chapter
    let allChapters: [Chapter]
    var initialPage: Int = 0
    var preloadedPages: [String]? = nil

    @State private var isLoading = true
    @State private var loadingProgress: Double = 0
    @State private var loadedPagesCount = 0
    @State private var totalPages = 0
    @State private var currentPage = 0
    @State private var showUI = true
    @State private var uiTimer: Timer?
    @State private var loadedChapters: [String] = []
    @State private var loadingNextChapter = false
    @State private var allPages: [(chapterSlug: String, url: String)] = []
    @State private var currentChapterSlug: String
    @State private var errorMessage: String?
    @State private var chapterBoundaries: [(slug: String, startIndex: Int)] = []
    @State private var visiblePage = 0

    init(manga: Manga, chapter: Chapter, allChapters: [Chapter], initialPage: Int = 0, preloadedPages: [String]? = nil) {
        self.manga = manga
        self.chapter = chapter
        self.allChapters = allChapters
        self.initialPage = initialPage
        self.preloadedPages = preloadedPages
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
                loadingView
            } else if let err = errorMessage, allPages.isEmpty {
                errorOverlay(err)
            } else if !isLoading && allPages.isEmpty {
                emptyPagesView
            } else {
                readerContent
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.7))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.5), radius: 4)
                    }
                    Spacer()
                }
                .padding(.top, 56)
                .padding(.leading, 16)
                Spacer()
            }

            if showUI && !allPages.isEmpty { topBar }
            VStack { Spacer(); bottomBar }
        }
        .ignoresSafeArea(edges: .bottom)
        .statusBarHidden(!showUI)
        .task { await loadInitialChapter() }
        .onAppear { resetUITimer() }
    }

    var loadingView: some View {
        VStack(spacing: 30) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "book.pages")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundColor(ZTheme.accent)
                if totalPages > 0 {
                    VStack(spacing: 12) {
                        ProgressView(value: loadingProgress)
                            .tint(ZTheme.accent)
                            .scaleEffect(x: 1, y: 2, anchor: .center)
                        Text("\(loadedPagesCount) / \(totalPages) pages")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ZTheme.textSecondary)
                    }
                    .padding(.horizontal, 40)
                } else {
                    ProgressView().tint(ZTheme.accent).scaleEffect(1.2)
                }
                Text("Preparing chapter...")
                    .font(.system(size: 13)).foregroundColor(ZTheme.textTertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    var readerContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(allPages.enumerated()), id: \.offset) { idx, page in
                        if let boundary = chapterBoundaries.first(where: { $0.startIndex == idx }), idx > 0 {
                            ChapterSeparator(number: manga.chapters.first(where: { $0.slug == boundary.slug })?.number ?? "??")
                                .id("sep_\(idx)")
                        }
                        MangaPageImage(url: page.url)
                            .id(idx)
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: PageOffsetKey.self,
                                    value: [idx: geo.frame(in: .named("reader_space")).minY])
                            })
                    }
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ScrollOffsetKey.self,
                        value: proxy.frame(in: .named("reader_space")).minY)
                })
            }
            .coordinateSpace(name: "reader_space")
            .onPreferenceChange(PageOffsetKey.self) { offsets in
                guard !offsets.isEmpty else { return }
                let closest = offsets.min(by: { abs($0.value) < abs($1.value) })
                if let closest = closest, closest.key != visiblePage {
                    visiblePage = closest.key
                    currentPage = visiblePage
                    saveProgress(pageIndex: visiblePage)
                    if visiblePage >= allPages.count - 5 && !loadingNextChapter {
                        Task { await loadNextChapter() }
                    }
                }
            }
            .onAppear { proxy.scrollTo(initialPage, anchor: .top) }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { showUI.toggle() }
                if showUI { resetUITimer() }
            }
        }
    }

    var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(manga.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                Text("Chapter \(currentChapterNumber)").font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            if !allPages.isEmpty {
                Text("\(currentPage + 1) / \(allPages.count)")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.55)).clipShape(Capsule())
            }
        }
        .padding(.horizontal, 60).padding(.top, 56).padding(.bottom, 14)
        .background(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom))
        .transition(.opacity)
    }

    var bottomBar: some View {
        Group {
            if !allPages.isEmpty {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.08))
                        Rectangle()
                            .fill(ZTheme.accent)
                            .frame(width: geo.size.width * CGFloat(currentPage + 1) / CGFloat(max(allPages.count, 1)))
                            .animation(.easeOut(duration: 0.15), value: currentPage)
                    }
                }
                .frame(height: 2)
            }
        }
    }

    var emptyPagesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed").font(.system(size: 44, weight: .ultraLight)).foregroundColor(.white.opacity(0.5))
            Text("No pages found").font(.system(size: 14)).foregroundColor(.white.opacity(0.6))
            Button("Go Back") { dismiss() }
                .font(.system(size: 15, weight: .semibold)).foregroundColor(ZTheme.bg)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(ZTheme.accent).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    func errorOverlay(_ err: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 44, weight: .ultraLight)).foregroundColor(ZTheme.danger)
            Text(err).font(.system(size: 14)).foregroundColor(.white.opacity(0.6)).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button("Retry") { Task { await loadInitialChapter() } }
                .font(.system(size: 15, weight: .semibold)).foregroundColor(ZTheme.bg)
                .padding(.horizontal, 24).padding(.vertical, 10).background(ZTheme.accent).clipShape(RoundedRectangle(cornerRadius: 10))
            Button("Go Back") { dismiss() }.foregroundColor(ZTheme.accent)
        }
    }

    func loadInitialChapter() async {
        isLoading = true; errorMessage = nil
        loadedPagesCount = 0; totalPages = 0; loadingProgress = 0

        let pagesToLoad: [String]
        if let preloaded = preloadedPages {
            pagesToLoad = preloaded
        } else if let local = DownloadManager.shared.getPages(mangaSlug: manga.slug, chapterSlug: chapter.slug) {
            pagesToLoad = local
        } else {
            do {
                let urls = try await MangaService.shared.fetchChapterPages(mangaSlug: manga.slug, chapterSlug: chapter.slug)
                pagesToLoad = urls
            } catch ZMangaError.cloudflareChallenge {
                await MainActor.run { errorMessage = "Cloudflare verification required."; isLoading = false }
                return
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
                return
            }
        }

        totalPages = pagesToLoad.count
        for i in 0..<pagesToLoad.count {
            await MainActor.run {
                loadedPagesCount = i + 1
                loadingProgress = Double(loadedPagesCount) / Double(totalPages)
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        await MainActor.run {
            allPages = pagesToLoad.map { (chapterSlug: chapter.slug, url: $0) }
            chapterBoundaries = [(slug: chapter.slug, startIndex: 0)]
            loadedChapters = [chapter.slug]
            isLoading = false
            loadedPagesCount = totalPages
            loadingProgress = 1.0
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
        let urls: [String]
        if let local = DownloadManager.shared.getPages(mangaSlug: manga.slug, chapterSlug: nextChapter.slug) {
            urls = local
        } else {
            do {
                urls = try await MangaService.shared.fetchChapterPages(mangaSlug: manga.slug, chapterSlug: nextChapter.slug)
            } catch {
                await MainActor.run { loadingNextChapter = false }
                return
            }
        }
        await MainActor.run {
            let startIndex = allPages.count
            allPages.append(contentsOf: urls.map { (chapterSlug: nextChapter.slug, url: $0) })
            chapterBoundaries.append((slug: nextChapter.slug, startIndex: startIndex))
            loadedChapters.append(nextChapter.slug)
            loadingNextChapter = false
        }
    }

    func saveProgress(pageIndex: Int) {
        let chapterSlug: String = {
            for b in chapterBoundaries.reversed() { if pageIndex >= b.startIndex { return b.slug } }
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

// MARK: - Preference Keys
struct PageOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct MangaPageImage: View {
    let url: String
    var body: some View {
        CachedAsyncImage(url: URL(string: url))
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .background(Color.black)
    }
}

struct ChapterSeparator: View {
    let number: String
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            Text("Chapter \(number)")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(ZTheme.accent)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(ZTheme.accent.opacity(0.1))
                .overlay(Capsule().stroke(ZTheme.accent.opacity(0.3), lineWidth: 1))
                .clipShape(Capsule())
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
        .padding(.horizontal, 20).padding(.vertical, 20)
        .background(Color.black)
    }
}