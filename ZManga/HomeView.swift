import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var latestManga: [Manga] = []
    @State private var popularManga: [Manga] = []
    @State private var isLoadingLatest = false
    @State private var isLoadingPopular = false
    @State private var latestPage = 1
    @State private var loadingMoreLatest = false
    @State private var heroIndex = 0

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        headerBar.padding(.bottom, 16)

                        // Hero banner
                        if !popularManga.isEmpty {
                            heroBanner
                                .padding(.bottom, 28)
                        }

                        if !store.history.isEmpty {
                            sectionLabel("واصل القراءة", icon: "clock.fill")
                            continueReadingSection.padding(.bottom, 28)
                        }

                        sectionLabel("الأكثر مشاهدة", icon: "flame.fill")
                        popularSection.padding(.bottom, 28)

                        sectionLabel("آخر التحديثات", icon: "bolt.fill")
                        latestSection

                        Color.clear.frame(height: 40)
                    }
                }
                .refreshable {
                    await loadLatest(reset: true)
                    await loadPopular()
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await loadLatest(reset: false)
            await loadPopular()
        }
        .onChange(of: store.reloadTrigger) { _ in
            Task {
                await loadLatest(reset: true)
                await loadPopular()
            }
        }
    }

    // MARK: - Header
    var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text("Z")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(ZTheme.goldGradient)
                    Text("مانجا")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(ZTheme.textPrimary)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                Text("lek-manga.net")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ZTheme.textTertiary)
                    .tracking(0.8)
            }
            Spacer()
            // Notification icon
            ZStack {
                Circle()
                    .fill(ZTheme.surface)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(ZTheme.border, lineWidth: 1))
                Image(systemName: "bell")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(ZTheme.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - Hero Banner
    var heroBanner: some View {
        ZStack(alignment: .bottom) {
            if let manga = popularManga.first {
                NavigationLink(destination: MangaDetailView(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL)) {
                    ZStack(alignment: .bottomLeading) {
                        CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                            .scaledToFill()
                            .frame(height: 260)
                            .clipped()
                            .overlay(
                                LinearGradient(
                                    colors: [.clear, .clear, ZTheme.bg.opacity(0.5), ZTheme.bg.opacity(0.92)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            if !manga.genres.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(manga.genres.prefix(2), id: \.self) { genre in
                                        Text(genre)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(ZTheme.bg)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(ZTheme.accent)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            Text(manga.title)
                                .font(.system(size: 22, weight: .black))
                                .foregroundColor(ZTheme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .environment(\.layoutDirection, .rightToLeft)

                            HStack(spacing: 8) {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(ZTheme.accent)
                                Text("ابدأ القراءة")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(ZTheme.accent)
                            }
                        }
                        .padding(20)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .overlay(
            Rectangle()
                .fill(ZTheme.accent.opacity(0.6))
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
        )
    }

    // MARK: - Section Label
    func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(ZTheme.accent)
                .frame(width: 3, height: 16)
                .clipShape(Capsule())
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ZTheme.accent)
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(ZTheme.textPrimary)
                .environment(\.layoutDirection, .rightToLeft)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Continue Reading
    var continueReadingSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
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
            if isLoadingPopular && popularManga.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { _ in SkeletonPopularCard() }
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
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
            if latestManga.isEmpty && isLoadingLatest {
                VStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonLatestRow()
                    }
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    if isLoadingLatest {
                        ProgressView()
                            .tint(ZTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(latestManga) { manga in
                            NavigationLink(destination: MangaDetailView(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL)) {
                                LatestUpdateRow(manga: manga)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onAppear {
                                if manga.id == latestManga.last?.id && !loadingMoreLatest {
                                    Task { await loadMoreLatest() }
                                }
                            }
                            Divider()
                                .background(ZTheme.border)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.horizontal, 0)

                if loadingMoreLatest {
                    HStack { Spacer(); ProgressView().tint(ZTheme.accent); Spacer() }
                        .padding(.vertical, 16)
                }
            }
        }
    }

    // MARK: - Fetch
    func loadLatest(reset: Bool = false) async {
        if reset {
            await MainActor.run {
                latestPage = 1
                isLoadingLatest = true
            }
        } else if latestManga.isEmpty {
            await MainActor.run { isLoadingLatest = true }
        }
        do {
            let items = try await MangaService.shared.fetchLatest(page: latestPage)
            await MainActor.run {
                if reset || latestManga.isEmpty {
                    latestManga = items
                } else {
                    latestManga.append(contentsOf: items)
                }
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
        let old = latestManga
        do {
            let items = try await MangaService.shared.fetchLatest(page: latestPage)
            await MainActor.run {
                latestManga = old + items
                loadingMoreLatest = false
            }
        } catch {
            await MainActor.run { loadingMoreLatest = false }
        }
    }

    func loadPopular() async {
        if popularManga.isEmpty {
            await MainActor.run { isLoadingPopular = true }
        }
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

// MARK: - Latest Update Row
struct LatestUpdateRow: View {
    let manga: Manga

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                .frame(width: 72, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ZTheme.border, lineWidth: 0.5)
                )

            VStack(alignment: .trailing, spacing: 5) {
                Text(manga.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ZTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)

                if let chapter = manga.latestChapterNumber {
                    HStack(spacing: 4) {
                        Text("فصل \(chapter)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ZTheme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let time = manga.lastUpdated {
                    Text(time)
                        .font(.system(size: 11))
                        .foregroundColor(ZTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if !manga.genres.isEmpty {
                    Text(manga.genres.prefix(2).joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundColor(ZTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ZTheme.bg)
    }
}

// MARK: - Popular Card
struct PopularCard: View {
    let manga: Manga
    @State private var pressed = false

    var body: some View {
        VStack(alignment: .center, spacing: 7) {
            ZStack(alignment: .topLeading) {
                CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                    .frame(width: 120, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(ZTheme.border, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
            }

            Text(manga.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ZTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 120)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .frame(width: 120)
        .scaleEffect(pressed ? 0.96 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: pressed)
    }
}

// MARK: - Continue Reading Card
struct ContinueReadingCard: View {
    let progress: ReadingProgress

    var body: some View {
        ZStack(alignment: .bottom) {
            CachedAsyncImage(url: URL(string: progress.mangaCover))
                .frame(width: 116, height: 164)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.95)],
                startPoint: .top, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Bottom accent line
            Rectangle()
                .fill(ZTheme.accent)
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .trailing, spacing: 2) {
                Text(progress.mangaTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                HStack(spacing: 4) {
                    Text("ف.\(progress.chapterNumber) · ص.\(progress.pageIndex + 1)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ZTheme.accentBright)
                    Image(systemName: "book.fill")
                        .font(.system(size: 8))
                        .foregroundColor(ZTheme.accentBright)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(8)
            .frame(width: 116, alignment: .trailing)
        }
        .frame(width: 116, height: 164)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
    }
}

// MARK: - Skeleton Cards
struct SkeletonPopularCard: View {
    @State private var shimmer = false
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(ZTheme.card)
            .frame(width: 120, height: 168)
            .overlay(shimmerOverlay)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { shimmer = true }
            }
    }
    var shimmerOverlay: some View {
        LinearGradient(
            colors: [Color.white.opacity(0), Color.white.opacity(0.05), Color.white.opacity(0)],
            startPoint: shimmer ? .topLeading : .bottomTrailing,
            endPoint: shimmer ? .bottomTrailing : .topLeading
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SkeletonLatestRow: View {
    @State private var shimmer = false
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(ZTheme.card).frame(width: 72, height: 100)
            VStack(alignment: .trailing, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(ZTheme.card).frame(height: 12)
                RoundedRectangle(cornerRadius: 4).fill(ZTheme.card).frame(width: 120, height: 12).frame(maxWidth: .infinity, alignment: .trailing)
                RoundedRectangle(cornerRadius: 4).fill(ZTheme.card).frame(width: 70, height: 10).frame(maxWidth: .infinity, alignment: .trailing)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(shimmerOverlay)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { shimmer = true }
        }
    }
    var shimmerOverlay: some View {
        LinearGradient(
            colors: [Color.white.opacity(0), Color.white.opacity(0.04), Color.white.opacity(0)],
            startPoint: shimmer ? .topLeading : .bottomTrailing,
            endPoint: shimmer ? .bottomTrailing : .topLeading
        )
    }
}