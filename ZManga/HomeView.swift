// HomeView.swift

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var network: NetworkMonitor
    @State private var latestManga: [Manga] = []
    @State private var popularManga: [Manga] = []
    @State private var isLoadingLatest = false
    @State private var isLoadingPopular = false
    @State private var latestPage = 1
    @State private var loadingMoreLatest = false

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()
                if !network.isConnected {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundColor(ZTheme.textTertiary)
                        Text("No Internet Connection")
                            .font(.system(size: 15))
                            .foregroundColor(ZTheme.textSecondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            headerBar.padding(.bottom, 20)

                            if !store.history.isEmpty {
                                sectionLabel("CONTINUE READING", icon: "clock.fill")
                                continueReadingSection.padding(.bottom, 24)
                            }

                            sectionLabel("POPULAR", icon: "flame.fill")
                            popularSection.padding(.bottom, 24)

                            sectionLabel("LATEST UPDATES", icon: "bolt.fill")
                            latestSection

                            Color.clear.frame(height: 32)
                        }
                    }
                    .refreshable {
                        await loadLatest(reset: true)
                        await loadPopular()
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            if let cachedLatest = store.cachedLatest, !cachedLatest.isEmpty { latestManga = cachedLatest }
            if let cachedPopular = store.cachedPopular, !cachedPopular.isEmpty { popularManga = cachedPopular }
            if network.isConnected {
                await loadLatest(reset: false)
                await loadPopular()
            }
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
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(ZTheme.textSecondary)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

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
            if isLoadingPopular && popularManga.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { _ in SkeletonPopularCard() }
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
            if latestManga.isEmpty && isLoadingLatest {
                VStack(spacing: 12) {
                    ForEach(0..<8, id: \.self) { _ in SkeletonLatestRow().frame(height: 122) }
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    if isLoadingLatest {
                        ProgressView().tint(ZTheme.accent).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    LazyVStack(spacing: 12) {
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
                        }
                    }
                }
                .padding(.horizontal, 16)

                if loadingMoreLatest {
                    HStack { Spacer(); ProgressView().tint(ZTheme.accent); Spacer() }.padding(.vertical, 16)
                }
            }
        }
    }

    // MARK: - Fetch Logic
    func loadLatest(reset: Bool = false) async {
        if reset { await MainActor.run { latestPage = 1; isLoadingLatest = true } }
        else if latestManga.isEmpty { await MainActor.run { isLoadingLatest = true } }
        do {
            let items = try await MangaService.shared.fetchLatest(page: latestPage)
            await MainActor.run {
                if reset || latestManga.isEmpty { latestManga = items } else { latestManga.append(contentsOf: items) }
                store.saveCachedLatest(latestManga)
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
                store.saveCachedLatest(latestManga)
                loadingMoreLatest = false
            }
        } catch {
            await MainActor.run { loadingMoreLatest = false }
        }
    }

    func loadPopular() async {
        if popularManga.isEmpty { await MainActor.run { isLoadingPopular = true } }
        do {
            let items = try await MangaService.shared.fetchPopular()
            await MainActor.run {
                popularManga = items
                store.saveCachedPopular(items)
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
            CachedAsyncImage(url: URL(string: progress.mangaCover))
                .frame(width: 116, height: 164)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.95)],
                startPoint: .top, endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
    }
}

// MARK: - Popular Card
struct PopularCard: View {
    let manga: Manga
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                .frame(width: 120, height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            Text(manga.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ZTheme.textPrimary)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
        }
        .frame(width: 120)
    }
}

// MARK: - Latest Update Row
struct LatestUpdateRow: View {
    let manga: Manga
    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                .frame(width: 80, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(manga.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ZTheme.textPrimary)
                    .lineLimit(2)
                if let chapter = manga.latestChapterNumber {
                    Text("Chapter \(chapter)")
                        .font(.system(size: 12))
                        .foregroundColor(ZTheme.accent)
                }
                if let time = manga.lastUpdated {
                    Text(time)
                        .font(.system(size: 11))
                        .foregroundColor(ZTheme.textTertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ZTheme.textTertiary)
        }
        .padding(12)
        .background(ZTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

// MARK: - Skeleton Cards
struct SkeletonPopularCard: View {
    @State private var shimmer = false
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(ZTheme.card)
            .frame(width: 120, height: 168)
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0), Color.white.opacity(0.05), Color.white.opacity(0)],
                    startPoint: shimmer ? .topLeading : .bottomTrailing,
                    endPoint: shimmer ? .bottomTrailing : .topLeading
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            )
            .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { shimmer = true } }
    }
}

struct SkeletonLatestRow: View {
    @State private var shimmer = false
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12).fill(ZTheme.card).frame(width: 80, height: 110)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(ZTheme.card).frame(height: 12)
                RoundedRectangle(cornerRadius: 4).fill(ZTheme.card).frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(ZTheme.card).frame(width: 80, height: 12)
            }
            Spacer()
        }
        .padding(12)
        .background(ZTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            LinearGradient(
                colors: [Color.white.opacity(0), Color.white.opacity(0.05), Color.white.opacity(0)],
                startPoint: shimmer ? .topLeading : .bottomTrailing,
                endPoint: shimmer ? .bottomTrailing : .topLeading
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { shimmer = true } }
    }
}