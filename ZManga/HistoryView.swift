import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var showClearAlert = false

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()

                if store.history.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("History")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ZTheme.textPrimary)
                }
                if !store.history.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showClearAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(ZTheme.danger)
                                .font(.system(size: 15))
                        }
                    }
                }
            }
            .toolbarBackground(ZTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Clear History", isPresented: $showClearAlert) {
                Button("Clear", role: .destructive) { store.clearHistory() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all reading history.")
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(ZTheme.textTertiary)
            Text("No reading history")
                .font(.system(size: 15))
                .foregroundColor(ZTheme.textSecondary)
            Text("Manga you read will appear here")
                .font(.system(size: 13))
                .foregroundColor(ZTheme.textTertiary)
        }
    }

    var historyList: some View {
        List {
            ForEach(store.history) { progress in
                NavigationLink(destination: MangaDetailView(slug: progress.mangaSlug, preloadTitle: progress.mangaTitle, preloadCover: progress.mangaCover)) {
                    HistoryRow(progress: progress)
                }
                .listRowBackground(ZTheme.surface)
                .listRowSeparatorTint(ZTheme.border)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .onDelete { indexSet in
                store.history.remove(atOffsets: indexSet)
            }
        }
        .listStyle(.plain)
        .background(ZTheme.bg)
        .scrollContentBackground(.hidden)
    }
}

struct HistoryRow: View {
    let progress: ReadingProgress

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: progress.lastRead, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: progress.mangaCover)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZTheme.card
                }
            }
            .frame(width: 50, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(progress.mangaTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ZTheme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text("Ch. \(progress.chapterNumber)")
                        .font(.system(size: 12))
                        .foregroundColor(ZTheme.accent)
                    Text("·")
                        .foregroundColor(ZTheme.textTertiary)
                    Text("Page \(progress.pageIndex + 1)")
                        .font(.system(size: 12))
                        .foregroundColor(ZTheme.textSecondary)
                }

                Text(timeAgo)
                    .font(.system(size: 11))
                    .foregroundColor(ZTheme.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }
}
