import SwiftUI

struct SearchView: View {
    @EnvironmentObject var network: NetworkMonitor
    @State private var query = ""
    @State private var results: [Manga] = []
    @State private var isLoading = false
    @State private var page = 1
    @State private var hasMore = true
    @State private var loadingMore = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedGenre: String? = nil

    let genres = ["درامـا", "رومانسى", "فانتازا", "أكشن", "كوميدى", "رعب", "خيال علمى", "مغامرات", "رياضة"]
    let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

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
                    VStack(spacing: 0) {
                        searchBar
                        genrePills
                        Divider().background(ZTheme.border)

                        if isLoading && results.isEmpty {
                            Spacer(); ProgressView().tint(ZTheme.accent); Spacer()
                        } else if results.isEmpty && !query.isEmpty {
                            emptyState
                        } else if results.isEmpty {
                            browsePrompt
                        } else {
                            resultsGrid
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }

    var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(ZTheme.textSecondary)

                TextField("", text: $query, prompt: Text("Search manga...").foregroundColor(ZTheme.textTertiary))
                    .foregroundColor(ZTheme.textPrimary)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: query) { newVal in
                        searchTask?.cancel()
                        if newVal.isEmpty {
                            results = []
                            return
                        }
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            if !Task.isCancelled { triggerSearch() }
                        }
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(ZTheme.textTertiary)
                            .font(.system(size: 15))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(ZTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ZTheme.border, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    var genrePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                GenrePill(title: "All", isSelected: selectedGenre == nil) {
                    selectedGenre = nil
                    results = []
                }
                ForEach(genres, id: \.self) { genre in
                    GenrePill(title: genre, isSelected: selectedGenre == genre) {
                        selectedGenre = genre
                        triggerGenreSearch(genre)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(results.enumerated()), id: \.offset) { index, manga in
                    NavigationLink(destination: MangaDetailView(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL)) {
                        SearchGridCard(manga: manga)
                            .id("search-\(manga.slug)-\(index)")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onAppear {
                        if index == results.count - 1 && !loadingMore && hasMore { loadMore() }
                    }
                }
            }
            .padding(16)
            if loadingMore { ProgressView().tint(ZTheme.accent).padding() }
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundColor(ZTheme.textTertiary)
            Text("No results for \"\(query)\"")
                .font(.system(size: 15))
                .foregroundColor(ZTheme.textSecondary)
            Spacer()
        }
    }

    var browsePrompt: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(ZTheme.textTertiary)
            Text("Search or browse by genre")
                .font(.system(size: 15))
                .foregroundColor(ZTheme.textSecondary)
            Spacer()
        }
    }

    func triggerSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        selectedGenre = nil
        page = 1; hasMore = true; results = []; isLoading = true
        Task {
            do {
                let items = try await MangaService.shared.search(query: query, page: 1)
                await MainActor.run { results = items; isLoading = false; hasMore = !items.isEmpty }
            } catch { await MainActor.run { isLoading = false } }
        }
    }

    func triggerGenreSearch(_ genre: String) {
        query = ""; selectedGenre = genre; page = 1; hasMore = true; results = []; isLoading = true
        let encoded = genre.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? genre
        Task {
            do {
                let items = try await MangaService.shared.fetchByGenre(genre: encoded)
                await MainActor.run { results = items.filter { !$0.coverURL.isEmpty && !$0.slug.contains("feed") }; isLoading = false; hasMore = !results.isEmpty }
            } catch { await MainActor.run { isLoading = false } }
        }
    }

    func loadMore() {
        loadingMore = true; page += 1
        Task {
            do {
                let items: [Manga]
                if let genre = selectedGenre {
                    let encoded = genre.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? genre
                    items = try await MangaService.shared.fetchByGenre(genre: encoded, page: page)
                } else {
                    items = try await MangaService.shared.search(query: query, page: page)
                }
                await MainActor.run { results.append(contentsOf: items); loadingMore = false; hasMore = !items.isEmpty }
            } catch { await MainActor.run { loadingMore = false } }
        }
    }
}

struct SearchGridCard: View {
    let manga: Manga
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                .aspectRatio(2/3, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            Text(manga.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ZTheme.textPrimary)
                .lineLimit(2)
        }
    }
}

struct GenrePill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? ZTheme.bg : ZTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? ZTheme.accent : ZTheme.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : ZTheme.border, lineWidth: 1))
        }
    }
}