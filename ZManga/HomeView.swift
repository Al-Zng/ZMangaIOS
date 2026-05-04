import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var latestManga: [Manga] = []
    @State private var popularManga: [Manga] = []
    @State private var isLoadingLatest = true
    @State private var isLoadingPopular = true
    @State private var errorMessage: String?
    @State private var latestPage = 1
    @State private var popularPage = 1
    @State private var loadingMoreLatest = false

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ZManga")
                                    .font(.system(size: 28, weight: .bold, design: .default))
                                    .foregroundColor(ZTheme.textPrimary)
                                Text("lek-manga.net")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(ZTheme.textTertiary)
                                    .tracking(1.5)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        // Continue Reading (if history exists)
                        if !store.history.isEmpty {
                            continueReadingSection
                        }

                        // Popular
                        sectionHeader("Popular")
                        popularSection

                        // Latest
                        sectionHeader("Latest Updates")
                        latestSection

                        Color.clear.frame(height: 20)
                    }
                }
                .refreshable {
                    await loadAll()
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await loadAll()
        }
    }

    // MARK: - Continue Reading
    var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Continue Reading")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.history.prefix(10)) { progress in
                        NavigationLink(destination: MangaDetailView(slug: progress.mangaSlug, preloadTitle: progress.mangaTitle)) {
                            ContinueReadingCard(progress: progress)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Popular Section
    var popularSection: some View {
        Group {
            if isLoadingPopular {
                HStack { Spacer(); ProgressView().tint(ZTheme.accent); Spacer() }
                    .frame(height: 120)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(popularManga.prefix(15)) { manga in
                            NavigationLink(destination: MangaDetailView(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL)) {
                                MangaCardVertical(manga: manga)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Latest Section
    var latestSection: some View {
        Group {
            if isLoadingLatest {
                HStack { Spacer(); ProgressView().tint(ZTheme.accent); Spacer() }
                    .frame(height: 120)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(latestManga) { manga in
                        NavigationLink(destination: MangaDetailView(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL)) {
                            MangaGridCard(manga: manga)
                        }
                        .onAppear {
                            if manga.id == latestManga.last?.id && !loadingMoreLatest {
                                Task { await loadMoreLatest() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                if loadingMoreLatest {
                    HStack { Spacer(); ProgressView().tint(ZTheme.accent); Spacer() }
                        .padding(.vertical, 12)
                }
            }
        }
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(ZTheme.textSecondary)
            .tracking(2)
            .padding(.horizontal, 20)
    }

    // MARK: - Load Data
    func loadAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadLatest(reset: true) }
            group.addTask { await loadPopular() }
        }
    }

    func loadLatest(reset: Bool = false) async {
        if reset { latestPage = 1 }
        isLoadingLatest = reset
        do {
            let items = try await MangaService.shared.fetchLatest(page: latestPage)
            await MainActor.run {
                if reset { latestManga = items } else { latestManga.append(contentsOf: items) }
                isLoadingLatest = false
            }
        } catch ZMangaError.cloudflareChallenge {
            await MainActor.run { isLoadingLatest = false }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoadingLatest = false
            }
        }
    }

    func loadMoreLatest() async {
        loadingMoreLatest = true
        latestPage += 1
        await loadLatest(reset: false)
        loadingMoreLatest = false
    }

    func loadPopular() async {
        isLoadingPopular = true
        do {
            let items = try await MangaService.shared.fetchPopular()
            await MainActor.run {
                popularManga = items
                isLoadingPopular = false
            }
        } catch {
            await MainActor.run { isLoadingPopular = false }
        }
    }
}

// MARK: - Continue Reading Card
struct ContinueReadingCard: View {
    let progress: ReadingProgress

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: URL(string: progress.mangaCover)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZTheme.card
                }
            }
            .frame(width: 120, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(progress.mangaTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text("Ch. \(progress.chapterNumber) · p.\(progress.pageIndex + 1)")
                    .font(.system(size: 10))
                    .foregroundColor(ZTheme.accent)
            }
            .padding(8)
            .frame(width: 120, alignment: .leading)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .frame(width: 120, height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Manga Card Vertical (Horizontal scroll)
struct MangaCardVertical: View {
    let manga: Manga

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: manga.coverURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    ZTheme.card.overlay(
                        Image(systemName: "photo").foregroundColor(ZTheme.textTertiary)
                    )
                default:
                    ZTheme.card.overlay(ProgressView().tint(ZTheme.accent))
                }
            }
            .frame(width: 110, height: 155)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(manga.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ZTheme.textPrimary)
                .lineLimit(2)
                .frame(width: 110, alignment: .leading)
        }
        .frame(width: 110)
    }
}

// MARK: - Manga Grid Card
struct MangaGridCard: View {
    let manga: Manga

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AsyncImage(url: URL(string: manga.coverURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    ZTheme.card.overlay(
                        Image(systemName: "photo").foregroundColor(ZTheme.textTertiary)
                    )
                default:
                    ZTheme.card.overlay(ProgressView().tint(ZTheme.accent).scaleEffect(0.6))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(2/3, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(manga.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ZTheme.textPrimary)
                .lineLimit(2)
        }
    }
}
