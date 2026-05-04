import SwiftUI

struct MangaDetailView: View {
    @EnvironmentObject var store: AppStore
    let slug: String
    var preloadTitle: String = ""
    var preloadCover: String = ""

    @State private var manga: Manga? = nil
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedChapter: Chapter? = nil
    @State private var showReader = false
    @State private var chapterSortAsc = false

    var sortedChapters: [Chapter] {
        guard let m = manga else { return [] }
        return chapterSortAsc
            ? m.chapters.sorted { (Int($0.number) ?? 0) < (Int($1.number) ?? 0) }
            : m.chapters.sorted { (Int($0.number) ?? 0) > (Int($1.number) ?? 0) }
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
        .fullScreenCover(isPresented: $showReader) {
            if let chapter = selectedChapter, let manga = manga {
                ReaderView(manga: manga, chapter: chapter, allChapters: sortedChapters)
                    .environmentObject(store)
            }
        }
        .task { await loadDetail() }
    }

    var loadingState: some View {
        VStack(spacing: 20) {
            // Skeleton header
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(ZTheme.card)
                    .frame(width: 110, height: 155)

                VStack(alignment: .leading, spacing: 8) {
                    Text(preloadTitle.isEmpty ? "Loading..." : preloadTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(ZTheme.textPrimary)
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
            Text(errorMessage ?? "Failed to load")
                .foregroundColor(ZTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") { Task { await loadDetail() } }
                .foregroundColor(ZTheme.accent)
        }
    }

    func content(manga: Manga) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero section
                heroSection(manga: manga)

                Divider().background(ZTheme.border).padding(.vertical, 20)

                // Description
                if !manga.description.isEmpty {
                    descriptionSection(manga.description)
                    Divider().background(ZTheme.border).padding(.vertical, 16)
                }

                // Chapters header
                chaptersHeader(count: manga.chapters.count)

                // Chapter list
                LazyVStack(spacing: 0) {
                    ForEach(sortedChapters) { chapter in
                        ChapterRow(
                            chapter: chapter,
                            manga: manga,
                            progress: store.history.first { $0.mangaSlug == manga.slug && $0.chapterSlug == chapter.slug }
                        ) {
                            selectedChapter = chapter
                            showReader = true
                        }
                        Divider().background(ZTheme.border).padding(.leading, 16)
                    }
                }

                Color.clear.frame(height: 40)
            }
        }
    }

    func heroSection(manga: Manga) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Cover
            AsyncImage(url: URL(string: manga.coverURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZTheme.card.overlay(
                        Image(systemName: "photo").foregroundColor(ZTheme.textTertiary)
                    )
                }
            }
            .frame(width: 110, height: 155)
            .clipShape(RoundedRectangle(cornerRadius: 10))

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
                    if !manga.rating.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(ZTheme.accent)
                            Text(manga.rating)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ZTheme.textSecondary)
                        }
                    }
                }

                // Genre tags
                if !manga.genres.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(manga.genres, id: \.self) { genre in
                            Text(genre)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(ZTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ZTheme.accentDim)
                                .clipShape(Capsule())
                        }
                    }
                }

                // Start reading button
                if let first = manga.chapters.max(by: { (Int($0.number) ?? 0) < (Int($1.number) ?? 0) }) {
                    Button {
                        let target = manga.chapters.min(by: { (Int($0.number) ?? 0) < (Int($1.number) ?? 0) }) ?? first
                        if let progress = store.history.first(where: { $0.mangaSlug == manga.slug }) {
                            selectedChapter = manga.chapters.first(where: { $0.slug == progress.chapterSlug }) ?? target
                        } else {
                            selectedChapter = target
                        }
                        showReader = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                            Text(store.history.first(where: { $0.mangaSlug == manga.slug }) != nil ? "Continue" : "Start Reading")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(ZTheme.bg)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(ZTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Spacer()
        }
        .padding(20)
    }

    func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Synopsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ZTheme.textSecondary)
                .tracking(2)
                .padding(.horizontal, 20)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(ZTheme.textSecondary)
                .lineSpacing(4)
                .padding(.horizontal, 20)
        }
    }

    func chaptersHeader(count: Int) -> some View {
        HStack {
            Text("\(count) CHAPTERS")
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
}

// MARK: - Chapter Row
struct ChapterRow: View {
    let chapter: Chapter
    let manga: Manga
    let progress: ReadingProgress?
    let action: () -> Void

    var isRead: Bool { progress != nil }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Chapter \(chapter.number)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isRead ? ZTheme.textTertiary : ZTheme.textPrimary)

                        if let p = progress {
                            Text("· p.\(p.pageIndex + 1)")
                                .font(.system(size: 12))
                                .foregroundColor(ZTheme.accent)
                        }
                    }

                    if !chapter.date.isEmpty {
                        Text(chapter.date)
                            .font(.system(size: 11))
                            .foregroundColor(ZTheme.textTertiary)
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

// MARK: - Status Badge
struct StatusBadge: View {
    let text: String

    var color: Color {
        text.lowercased().contains("مستمر") || text.lowercased().contains("ongoing")
            ? Color(hex: "#4CAF82")
            : ZTheme.textTertiary
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
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
