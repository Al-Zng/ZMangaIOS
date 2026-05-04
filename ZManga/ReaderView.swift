import SwiftUI

struct ReaderView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    let manga: Manga
    let chapter: Chapter
    let allChapters: [Chapter] // sorted newest first

    @State private var pages: [String] = []
    @State private var isLoading = true
    @State private var currentPage = 0
    @State private var showUI = true
    @State private var uiTimer: Timer?
    @State private var loadedChapters: [String] = [] // slugs of loaded chapters
    @State private var loadingNextChapter = false
    @State private var allPages: [(chapterSlug: String, url: String)] = []
    @State private var currentChapterSlug: String
    @State private var errorMessage: String?
    @State private var savedPageIndex = 0

    // Track which chapter's pages we're in
    @State private var chapterBoundaries: [(slug: String, startIndex: Int)] = []

    init(manga: Manga, chapter: Chapter, allChapters: [Chapter]) {
        self.manga = manga
        self.chapter = chapter
        self.allChapters = allChapters
        _currentChapterSlug = State(initialValue: chapter.slug)
    }

    var currentChapterNumber: String {
        let boundaries = chapterBoundaries
        guard let lastBoundary = boundaries.last(where: { $0.startIndex <= currentPage }) else {
            return chapter.number
        }
        return manga.chapters.first(where: { $0.slug == lastBoundary.slug })?.number ?? chapter.number
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if isLoading && allPages.isEmpty {
                loadingOverlay
            } else if let err = errorMessage {
                errorOverlay(err)
            } else {
                // Infinite scroll reader
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(allPages.enumerated()), id: \.offset) { idx, page in
                            // Chapter separator
                            if let boundary = chapterBoundaries.first(where: { $0.startIndex == idx }), idx > 0 {
                                ChapterSeparator(
                                    number: manga.chapters.first(where: { $0.slug == boundary.slug })?.number ?? "??"
                                )
                            }

                            PageImageView(url: page.url)
                                .onAppear {
                                    currentPage = idx
                                    saveProgress(pageIndex: idx)

                                    // Load next chapter when near end
                                    if idx >= allPages.count - 4 && !loadingNextChapter {
                                        Task { await loadNextChapter() }
                                    }
                                }
                        }

                        if loadingNextChapter {
                            ProgressView()
                                .tint(ZTheme.accent)
                                .padding(40)
                        }
                    }
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showUI.toggle()
                    }
                    resetUITimer()
                }
            }

            // Top UI overlay
            if showUI {
                topBar
            }

            // Bottom progress bar (always visible)
            VStack {
                Spacer()
                bottomBar
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .statusBarHidden(!showUI)
        .task {
            await loadInitialChapter()
        }
        .onAppear {
            resetUITimer()
            // Restore progress if any
            if let progress = store.history.first(where: {
                $0.mangaSlug == manga.slug && $0.chapterSlug == chapter.slug
            }) {
                savedPageIndex = progress.pageIndex
            }
        }
    }

    var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(manga.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("Chapter \(currentChapterNumber)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Page counter
            if !allPages.isEmpty {
                Text("\(currentPage + 1) / \(allPages.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 12)
        .background(
            LinearGradient(colors: [.black.opacity(0.7), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    var bottomBar: some View {
        Group {
            if !allPages.isEmpty {
                VStack(spacing: 0) {
                    // Thin progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                            Rectangle()
                                .fill(ZTheme.accent)
                                .frame(width: geo.size.width * CGFloat(currentPage + 1) / CGFloat(allPages.count))
                        }
                    }
                    .frame(height: 2)
                }
            }
        }
    }

    var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView().tint(ZTheme.accent).scaleEffect(1.5)
            Text("Loading chapter...")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    func errorOverlay(_ err: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundColor(ZTheme.danger)
            Text(err)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") { Task { await loadInitialChapter() } }
                .foregroundColor(ZTheme.accent)
        }
    }

    // MARK: - Load Chapter
    func loadInitialChapter() async {
        isLoading = true
        errorMessage = nil
        do {
            let urls = try await MangaService.shared.fetchChapterPages(
                mangaSlug: manga.slug, chapterSlug: chapter.slug
            )
            await MainActor.run {
                let newPages = urls.map { (chapterSlug: chapter.slug, url: $0) }
                allPages = newPages
                chapterBoundaries = [(slug: chapter.slug, startIndex: 0)]
                loadedChapters = [chapter.slug]
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

    func loadNextChapter() async {
        // Find the next chapter (lower number = next in reading order)
        guard let currentBoundary = chapterBoundaries.last else { return }
        let loadedSlugs = Set(loadedChapters)

        // allChapters is sorted newest first, so next to read = lower index that hasn't been loaded
        guard let currentIdx = allChapters.firstIndex(where: { $0.slug == currentBoundary.slug }),
              currentIdx + 1 < allChapters.count else { return }

        let nextChapter = allChapters[currentIdx + 1]
        guard !loadedSlugs.contains(nextChapter.slug) else { return }

        loadingNextChapter = true
        do {
            let urls = try await MangaService.shared.fetchChapterPages(
                mangaSlug: manga.slug, chapterSlug: nextChapter.slug
            )
            await MainActor.run {
                let startIndex = allPages.count
                let newPages = urls.map { (chapterSlug: nextChapter.slug, url: $0) }
                allPages.append(contentsOf: newPages)
                chapterBoundaries.append((slug: nextChapter.slug, startIndex: startIndex))
                loadedChapters.append(nextChapter.slug)
                loadingNextChapter = false
            }
        } catch {
            await MainActor.run { loadingNextChapter = false }
        }
    }

    // MARK: - Save Progress
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
            mangaSlug: manga.slug,
            mangaTitle: manga.title,
            mangaCover: manga.coverURL,
            chapterSlug: chapterSlug,
            chapterNumber: chapterNum,
            pageIndex: localPageIndex
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

// MARK: - Page Image View
struct PageImageView: View {
    let url: String
    @State private var failedToLoad = false

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width)
                case .failure:
                    ZStack {
                        Color.black
                        VStack(spacing: 8) {
                            Image(systemName: "photo.slash")
                                .font(.system(size: 28, weight: .ultraLight))
                                .foregroundColor(.white.opacity(0.3))
                            Text("Failed to load image")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.width * 1.5)
                default:
                    ZStack {
                        Color.black
                        ProgressView().tint(ZTheme.accent)
                    }
                    .frame(width: geo.size.width, height: geo.size.width * 1.5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Chapter Separator
struct ChapterSeparator: View {
    let number: String

    var body: some View {
        HStack {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            Text("Chapter \(number)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ZTheme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "#1A1A00"))
                .clipShape(Capsule())
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.black)
    }
}