import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var latestManga: [Manga] = []
    @State private var popularManga: [Manga] = []
    @State private var isLoadingLatest = true
    @State private var isLoadingPopular = true
    @State private var latestPage = 1
    @State private var loadingMoreLatest = false

    let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header Bar
                        headerBar
                            .padding(.bottom, 20)

                        // Continue Reading
                        if !store.history.isEmpty {
                            sectionLabel("CONTINUE READING", icon: "clock.fill")
                            continueReadingSection
                                .padding(.bottom, 24)
                        }

                        // Popular
                        sectionLabel("POPULAR", icon: "flame.fill")
                        popularSection
                            .padding(.bottom, 24)

                        // Latest
                        sectionLabel("LATEST UPDATES", icon: "bolt.fill")
                        latestSection

                        Color.clear.frame(height: 32)
                    }
                }
                .refreshable {
                    await loadAll()
                }
            }
            .navigationBarHidden(true)
        }
        .task { await loadAll() }
        .onChange(of: store.reloadTrigger) { _ in
            Task { await loadAll() }
        }
    }

    // MARK: - Header
    var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .foregroundColor(ZTheme.accent)
                        .font(.system(size: 18, weight: .bold))
                    Text("ZManga")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(ZTheme.textPrimary)
                }
                Text("lek-manga.net")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(ZTheme.textTertiary)
                    .tracking(1.2)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Section Label
    func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(ZTheme.accent)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ZTheme.textSecondary)
                .tracking(1.5)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Continue Reading
    var continueReadingSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.history.prefix(10)) { progress in
                    NavigationLink(destination: MangaDetailView(slug: progress.mangaSlug, preloadTitle: progress.mangaTitle)) {
                        ContinueReadingCard(progress: progress)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Popular
    var popularSection: some View {
        Group {
            if isLoadingPopular {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { _ in
                            SkeletonCard()
                        }
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(popularManga.prefix(20)) { manga in
                            NavigationLink(destination: MangaDetailView(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL)) {
                                PopularCard(manga: manga)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Latest
    var latestSection: some View {
        Group {
            if isLoadingLatest {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(0..<12, id: \.self) { _ in
                        SkeletonGridCard()
                    }
                }
                .padding(.horizontal, 16)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(latestManga) { manga in
                        NavigationLink(destination: MangaDetailView(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL)) {
                            LatestGridCard(manga: manga)
                        }
                        .buttonStyle(PlainButtonStyle())
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
                        .padding(.vertical, 16)
                }
            }
        }
    }

    // MARK: - Fetch
    func loadAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadLatest(reset: true) }
            group.addTask { await loadPopular() }
        }
    }

    func loadLatest(reset: Bool = false) async {
        if reset { latestPage = 1 }
        if reset { await MainActor.run { isLoadingLatest = true } }
        do {
            let items = try await MangaService.shared.fetchLatest(page: latestPage)
            await MainActor.run {
                if reset { latestManga = items } else { latestManga.append(contentsOf: items) }
                isLoadingLatest = false
            }
        } catch {
            await MainActor.run { isLoadingLatest = false }
        }
    }

    func loadMoreLatest() async {
        guard !loadingMoreLatest else { return }
        await MainActor.run { loadingMoreLatest = true }
        latestPage += 1
        await loadLatest(reset: false)
        await MainActor.run { loadingMoreLatest = false }
    }

    func loadPopular() async {
        await MainActor.run { isLoadingPopular = true }
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
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: ZTheme.card
                }
            }
            .frame(width: 116, height: 164)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.95)],
                startPoint: .top, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(progress.mangaTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 8))
                        .foregroundColor(ZTheme.accentBright)
                    Text("Ch.\(progress.chapterNumber) · p.\(progress.pageIndex + 1)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ZTheme.accentBright)
                }
            }
            .padding(8)
            .frame(width: 116, alignment: .leading)
        }
        .frame(width: 116, height: 164)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Popular Card (Landscape style)
struct PopularCard: View {
    let manga: Manga

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AsyncImage(url: URL(string: manga.coverURL)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    ZTheme.card.overlay(Image(systemName: "photo").foregroundColor(ZTheme.textTertiary))
                default:
                    ZTheme.card.overlay(ProgressView().tint(ZTheme.accent).scaleEffect(0.7))
                }
            }
            .frame(width: 120, height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ZTheme.border, lineWidth: 0.5)
            )

            Text(manga.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ZTheme.textPrimary)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
        }
        .frame(width: 120)
    }
}

// MARK: - Latest Grid Card
struct LatestGridCard: View {
    let manga: Manga

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: manga.coverURL)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    ZTheme.card.overlay(Image(systemName: "photo").foregroundColor(ZTheme.textTertiary))
                default:
                    ZTheme.card.overlay(ProgressView().tint(ZTheme.accent).scaleEffect(0.6))
                }
            }
            .aspectRatio(2/3, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ZTheme.border, lineWidth: 0.5)
            )

            Text(manga.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ZTheme.textPrimary)
                .lineLimit(2)
        }
    }
}

// MARK: - Skeleton Views
struct SkeletonCard: View {
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(ZTheme.card)
            .frame(width: 120, height: 168)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0), Color.white.opacity(0.05), Color.white.opacity(0)],
                            startPoint: shimmer ? .topLeading : .bottomTrailing,
                            endPoint: shimmer ? .bottomTrailing : .topLeading
                        )
                    )
            )
            .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { shimmer = true } }
    }
}

struct SkeletonGridCard: View {
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(ZTheme.card)
                .aspectRatio(2/3, contentMode: .fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0), Color.white.opacity(0.04), Color.white.opacity(0)],
                                startPoint: shimmer ? .topLeading : .bottomTrailing,
                                endPoint: shimmer ? .bottomTrailing : .topLeading
                            )
                        )
                )
            RoundedRectangle(cornerRadius: 3).fill(ZTheme.card).frame(height: 10)
            RoundedRectangle(cornerRadius: 3).fill(ZTheme.card).frame(width: 60, height: 10)
        }
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { shimmer = true } }
    }
}