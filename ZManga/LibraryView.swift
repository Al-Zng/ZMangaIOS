import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var store: AppStore
    @State private var sortOption: SortOption = .dateAdded

    enum SortOption: String, CaseIterable {
        case dateAdded = "تاريخ الإضافة"
        case title = "الاسم"
    }

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var sortedLibrary: [Manga] {
        switch sortOption {
        case .dateAdded: return store.library
        case .title: return store.library.sorted { $0.title < $1.title }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()

                if store.library.isEmpty {
                    emptyState
                } else {
                    libraryGrid
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("مكتبتي")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ZTheme.textPrimary)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                if !store.library.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if sortOption == option {
                                            Image(systemName: "checkmark")
                                        }
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
        VStack(spacing: 16) {
            Image(systemName: "heart")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundColor(ZTheme.textTertiary)
            Text("مكتبتك فارغة")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ZTheme.textSecondary)
                .environment(\.layoutDirection, .rightToLeft)
            Text("أضف المانجا من صفحتها بالضغط على ♥")
                .font(.system(size: 13))
                .foregroundColor(ZTheme.textTertiary)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    var libraryGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(sortedLibrary) { manga in
                    NavigationLink(destination: MangaDetailView(slug: manga.slug, preloadTitle: manga.title, preloadCover: manga.coverURL)) {
                        LibraryCard(manga: manga)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            store.removeFromLibrary(manga)
                        } label: {
                            Label("إزالة", systemImage: "heart.slash")
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}

struct LibraryCard: View {
    let manga: Manga

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(url: URL(string: manga.highQualityCoverURL))
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundColor(ZTheme.accent)
                    .padding(5)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
                    .padding(5)
            }

            Text(manga.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(ZTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}