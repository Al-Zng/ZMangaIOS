import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedCategory: Category = .favorites
    @State private var sortOption: SortOption = .dateAdded

    enum Category: String, CaseIterable {
        case favorites = "Favorites"
        case wantToRead = "Want to Read"
        case completed = "Completed"
        case downloaded = "Downloaded"
    }

    enum SortOption: String, CaseIterable {
        case dateAdded = "Date Added"
        case title = "Title"
    }

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var displayedManga: [Manga] {
        let list: [Manga]
        switch selectedCategory {
        case .favorites: list = store.library
        case .wantToRead: list = store.wantToRead
        case .completed: list = store.completed
        case .downloaded:
            let slugs = Set(DownloadManager.shared.downloads.values.map { $0.mangaSlug })
            return (store.library + store.wantToRead + store.completed).filter { slugs.contains($0.slug) }
        }
        switch sortOption {
        case .dateAdded: return list
        case .title: return list.sorted { $0.title < $1.title }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Category picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Category.allCases, id: \.self) { cat in
                                CategoryPill(title: cat.rawValue, isSelected: selectedCategory == cat) {
                                    selectedCategory = cat
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(ZTheme.surface)

                    Divider().background(ZTheme.border)

                    if displayedManga.isEmpty {
                        emptyState
                    } else {
                        libraryGrid
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Library")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ZTheme.textPrimary)
                }
                if !displayedManga.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if sortOption == option { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .foregroundColor(ZTheme.textSecondary)
                                .font(.system(size: 15))
                        }
                    }
                }
            }
            .toolbarBackground(ZTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(ZTheme.textTertiary)
            Text("No manga here")
                .font(.system(size: 15))
                .foregroundColor(ZTheme.textSecondary)
            Spacer()
        }
    }

    var libraryGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(displayedManga) { manga in
                    NavigationLink(destination: MangaDetailView(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL)) {
                        LibraryCard(manga: manga)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            removeFromCurrentCategory(manga)
                        } label: {
                            Label("Remove", systemImage: "heart.slash")
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    func removeFromCurrentCategory(_ manga: Manga) {
        switch selectedCategory {
        case .favorites: store.removeFromLibrary(manga)
        case .wantToRead: store.removeWantToRead(manga)
        case .completed: store.removeCompleted(manga)
        case .downloaded: break // يمكن إضافة حذف جميع التحميلات إذا أردت
        }
    }
}

struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? ZTheme.bg : ZTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? ZTheme.accent : ZTheme.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : ZTheme.border, lineWidth: 1))
        }
    }
}

struct LibraryCard: View {
    let manga: Manga
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundColor(ZTheme.accent)
                    .padding(5)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .padding(6)
            }
            Text(manga.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ZTheme.textPrimary)
                .lineLimit(2)
        }
    }
}