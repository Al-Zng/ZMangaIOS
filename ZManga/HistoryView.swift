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
                    Text("سجل القراءة")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ZTheme.textPrimary)
                        .environment(\.layoutDirection, .rightToLeft)
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
            .alert("مسح السجل", isPresented: $showClearAlert) {
                Button("مسح", role: .destructive) { store.clearHistory() }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("سيتم حذف جميع سجل القراءة.")
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundColor(ZTheme.textTertiary)
            Text("لا يوجد سجل قراءة")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ZTheme.textSecondary)
                .environment(\.layoutDirection, .rightToLeft)
            Text("المانجا التي تقرأها ستظهر هنا")
                .font(.system(size: 13))
                .foregroundColor(ZTheme.textTertiary)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    var historyList: some View {
        List {
            ForEach(store.history) { progress in
                NavigationLink(destination: MangaDetailView(slug: progress.mangaSlug, preloadTitle: progress.mangaTitle, preloadCover: progress.mangaCover)) {
                    HistoryRow(progress: progress)
                }
                .listRowBackground(ZTheme.bg)
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
        formatter.locale = Locale(identifier: "ar")
        return formatter.localizedString(for: progress.lastRead, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(progress.mangaTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ZTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .environment(\.layoutDirection, .rightToLeft)

                HStack(spacing: 4) {
                    Text(timeAgo)
                        .font(.system(size: 11))
                        .foregroundColor(ZTheme.textTertiary)
                    Text("·")
                        .foregroundColor(ZTheme.textTertiary)
                    Text("ص. \(progress.pageIndex + 1)")
                        .font(.system(size: 12))
                        .foregroundColor(ZTheme.textSecondary)
                    Text("·")
                        .foregroundColor(ZTheme.textTertiary)
                    Text("ف. \(progress.chapterNumber)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ZTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)

            CachedAsyncImage(url: URL(string: progress.mangaCover))
                .frame(width: 50, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(ZTheme.border, lineWidth: 0.5)
                )
        }
        .padding(.vertical, 10)
    }
}