import Foundation
import SwiftUI

// MARK: - Manga Model
struct Manga: Identifiable, Codable, Hashable {
    var id: String { slug }
    let slug: String
    var title: String
    var coverURL: String
    var genres: [String]
    var status: String
    var rating: String
    var description: String
    var chapters: [Chapter]
    var author: String
    var artist: String

    var latestChapterNumber: String?
    var lastUpdated: String?

    var highQualityCoverURL: String {
        let patterns = ["-110x150", "-150x200", "-200x300", "-300x450", "-193x278", "-350x476"]
        var url = coverURL
        for pattern in patterns {
            if url.contains(pattern) {
                url = url.replacingOccurrences(of: pattern, with: "")
                break
            }
        }
        return url
    }

    init(slug: String, title: String, coverURL: String = "", genres: [String] = [],
         status: String = "", rating: String = "", description: String = "",
         chapters: [Chapter] = [], author: String = "", artist: String = "",
         latestChapterNumber: String? = nil, lastUpdated: String? = nil) {
        self.slug = slug
        self.title = title
        self.coverURL = coverURL
        self.genres = genres
        self.status = status
        self.rating = rating
        self.description = description
        self.chapters = chapters
        self.author = author
        self.artist = artist
        self.latestChapterNumber = latestChapterNumber
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Chapter Model
struct Chapter: Identifiable, Codable, Hashable {
    var id: String { slug }
    let slug: String
    var number: String
    var title: String
    var date: String
    var pages: [String]

    init(slug: String, number: String, title: String = "", date: String = "", pages: [String] = []) {
        self.slug = slug
        self.number = number
        self.title = title
        self.date = date
        self.pages = pages
    }
}

// MARK: - Reading Progress
struct ReadingProgress: Identifiable, Codable {
    var id = UUID()
    var mangaSlug: String
    var mangaTitle: String
    var mangaCover: String
    var chapterSlug: String
    var chapterNumber: String
    var pageIndex: Int
    var lastRead: Date

    init(mangaSlug: String, mangaTitle: String, mangaCover: String,
         chapterSlug: String, chapterNumber: String, pageIndex: Int) {
        self.id = UUID()
        self.mangaSlug = mangaSlug
        self.mangaTitle = mangaTitle
        self.mangaCover = mangaCover
        self.chapterSlug = chapterSlug
        self.chapterNumber = chapterNumber
        self.pageIndex = pageIndex
        self.lastRead = Date()
    }
}

// MARK: - Download Manager (موجود لديك)
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    @Published var downloads: [String: DownloadedChapter] = [:]
    @Published var activeDownloads: [String: Double] = [:]
    private let downloadsKey = "zmanga_downloads"
    init() { load() }

    struct DownloadedChapter: Codable, Identifiable {
        var id: String { "\(mangaSlug)_\(chapterSlug)" }
        let mangaSlug: String
        let chapterSlug: String
        let chapterNumber: String
        let mangaTitle: String
        let pages: [String]
        let downloadedAt: Date
    }

    func isDownloaded(mangaSlug: String, chapterSlug: String) -> Bool {
        downloads["\(mangaSlug)_\(chapterSlug)"] != nil
    }
    func isDownloading(mangaSlug: String, chapterSlug: String) -> Bool {
        activeDownloads["\(mangaSlug)_\(chapterSlug)"] != nil
    }
    func progress(mangaSlug: String, chapterSlug: String) -> Double {
        activeDownloads["\(mangaSlug)_\(chapterSlug)"] ?? 0
    }

    @MainActor
    func downloadChapter(manga: Manga, chapter: Chapter, pages: [String]) async { ... }
    func deleteChapter(mangaSlug: String, chapterSlug: String) { ... }
    func getPages(mangaSlug: String, chapterSlug: String) -> [String]? { ... }
    private func getChapterDir(mangaSlug: String, chapterSlug: String) -> URL { ... }
    private func save() { ... }
    private func load() { ... }
}

// MARK: - AppStore
class AppStore: ObservableObject {
    static weak var currentStore: AppStore?
    @Published var history: [ReadingProgress] = []
    @Published var library: [Manga] = []
    @Published var showCloudflareSheet = false
    @Published var cloudflareURL: URL? = nil
    @Published var cookiesReady = false
    @Published var reloadTrigger = 0
    private let historyKey = "zmanga_history"
    private let libraryKey = "zmanga_library"
    init() { loadHistory(); loadLibrary() }

    func saveProgress(_ progress: ReadingProgress) { ... }
    func clearHistory() { ... }
    private func persistHistory() { ... }
    private func loadHistory() { ... }
    func addToLibrary(_ manga: Manga) { ... }
    func removeFromLibrary(_ manga: Manga) { ... }
    func isInLibrary(_ manga: Manga) -> Bool { ... }
    private func persistLibrary() { ... }
    private func loadLibrary() { ... }
    func triggerCloudflare(url: URL) { cloudflareURL = url; showCloudflareSheet = true }
    func triggerReload() { reloadTrigger += 1 }
}

// MARK: - Design Tokens (بالعربي كما في مشروعك)
struct ZTheme {
    static let bg       = Color(hex: "#0D0D0D")
    static let surface  = Color(hex: "#161616")
    static let card     = Color(hex: "#1C1C1C")
    static let cardHover = Color(hex: "#242424")
    static let border      = Color(hex: "#2A2A2A")
    static let borderLight = Color(hex: "#383838")
    static let accent       = Color(hex: "#F5A623")
    static let accentBright = Color(hex: "#FFB940")
    static let accentDim    = Color(hex: "#F5A623").opacity(0.15)
    static let textPrimary   = Color(hex: "#F0F0F0")
    static let textSecondary = Color(hex: "#8A8A8A")
    static let textTertiary  = Color(hex: "#4A4A4A")
    static let danger  = Color(hex: "#E85A6A")
    static let success = Color(hex: "#4CAF82")
    static let warning = Color(hex: "#F5A623")
    static let goldGradient = LinearGradient(
        colors: [Color(hex: "#F5A623"), Color(hex: "#E8850A")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: String) { ... }
}

// MARK: - Cached Async Image (مع Referer وإعادة المحاولة)
struct CachedAsyncImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var attempt = 0

    private static let cache = URLCache(memoryCapacity: 80*1024*1024, diskCapacity: 400*1024*1024)

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image).resizable().interpolation(.high).antialiased(true)
            } else if isLoading && attempt < 3 {
                Rectangle().fill(Color(white:0.12)).overlay(ProgressView().tint(ZTheme.accent))
            } else {
                Rectangle().fill(Color(white:0.12)).overlay(Image(systemName:"photo").font(.title2).foregroundColor(.gray))
            }
        }
        .task(id: url?.absoluteString) { await loadImage() }
    }

    private func loadImage() async {
        guard let url = url else { isLoading=false; loadFailed=true; return }
        let urlStr = url.absoluteString.lowercased()
        if urlStr.contains("lekmanga.png") || urlStr.contains("-512.png") || urlStr.contains("/favicon") {
            isLoading=false; loadFailed=true; return
        }
        let config = URLSessionConfiguration.default
        config.urlCache = Self.cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        for _ in 0..<3 {
            attempt += 1
            var req = URLRequest(url: url)
            req.setValue("https://lekmanga.site", forHTTPHeaderField: "Referer")
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            do {
                let (data, resp) = try await session.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200, let img = UIImage(data: data), img.size.width > 0 {
                    await MainActor.run { image = img; isLoading = false }
                    return
                }
            } catch { try? await Task.sleep(nanoseconds: 500_000_000) }
        }
        await MainActor.run { loadFailed = true; isLoading = false }
    }
}