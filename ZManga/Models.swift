import Foundation
import SwiftUI
import WebKit

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

// MARK: - Download Manager (مع غلاف وحجم)
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
        let mangaCover: String
        let pages: [String]
        let downloadedAt: Date
    }

    var downloadedSize: Int64 {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsDir = base.appendingPathComponent("downloads")
        return folderSize(at: downloadsDir)
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
    func downloadChapter(manga: Manga, chapter: Chapter, pages: [String]? = nil) async {
        let key = "\(manga.slug)_\(chapter.slug)"
        guard !isDownloaded(mangaSlug: manga.slug, chapterSlug: chapter.slug),
              !isDownloading(mangaSlug: manga.slug, chapterSlug: chapter.slug) else { return }

        activeDownloads[key] = 0.0
        let dir = getChapterDir(mangaSlug: manga.slug, chapterSlug: chapter.slug)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let urls: [String]
        if let pages = pages {
            urls = pages
        } else {
            guard let fetched = try? await MangaService.shared.fetchChapterPages(mangaSlug: manga.slug, chapterSlug: chapter.slug) else {
                activeDownloads.removeValue(forKey: key)
                return
            }
            urls = fetched
        }

        var localPaths: [String] = []
        let session = URLSession.shared
        for (idx, urlStr) in urls.enumerated() {
            guard let url = URL(string: urlStr) else { continue }
            do {
                let (data, _) = try await session.data(from: url)
                let filePath = dir.appendingPathComponent("\(idx).jpg")
                try data.write(to: filePath)
                localPaths.append(filePath.path)
            } catch {
                localPaths.append(urlStr)
            }
            activeDownloads[key] = Double(idx + 1) / Double(urls.count)
        }

        let downloaded = DownloadedChapter(
            mangaSlug: manga.slug,
            chapterSlug: chapter.slug,
            chapterNumber: chapter.number,
            mangaTitle: manga.title,
            mangaCover: manga.coverURL,
            pages: localPaths,
            downloadedAt: Date()
        )
        downloads[key] = downloaded
        activeDownloads.removeValue(forKey: key)
        save()
    }

    func deleteChapter(mangaSlug: String, chapterSlug: String) {
        let key = "\(mangaSlug)_\(chapterSlug)"
        let dir = getChapterDir(mangaSlug: mangaSlug, chapterSlug: chapterSlug)
        try? FileManager.default.removeItem(at: dir)
        downloads.removeValue(forKey: key)
        save()
    }

    func removeAllDownloads() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsDir = base.appendingPathComponent("downloads")
        try? FileManager.default.removeItem(at: downloadsDir)
        downloads.removeAll()
        save()
    }

    func getPages(mangaSlug: String, chapterSlug: String) -> [String]? {
        downloads["\(mangaSlug)_\(chapterSlug)"]?.pages
    }

    private func getChapterDir(mangaSlug: String, chapterSlug: String) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("downloads/\(mangaSlug)/\(chapterSlug)")
    }

    private func folderSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += Int64(fileSize)
            }
        }
        return size
    }

    private func save() {
        if let data = try? JSONEncoder().encode(downloads) {
            UserDefaults.standard.set(data, forKey: downloadsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: downloadsKey),
              let decoded = try? JSONDecoder().decode([String: DownloadedChapter].self, from: data) else { return }
        downloads = decoded
    }
}

// MARK: - كائن تحدي Cloudflare (يدعم Identifiable للـ sheet)
struct CloudflareChallenge: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - AppStore (مُعدّل للعمل مع Cloudflare بشكل صحيح)
class AppStore: ObservableObject {
    static var currentStore: AppStore?
    @Published var history: [ReadingProgress] = []
    @Published var library: [Manga] = []
    @Published var wantToRead: [Manga] = []
    @Published var completed: [Manga] = []
    @Published var activeChallenge: CloudflareChallenge? = nil
    @Published var cookiesReady = false
    @Published var reloadTrigger = 0
    @Published var cachedLatest: [Manga]?
    @Published var cachedPopular: [Manga]?
    @Published var mangaCache: [String: Manga] = [:]

    private let historyKey = "zmanga_history"
    private let libraryKey = "zmanga_library"
    private let wantToReadKey = "zmanga_wanttoread"
    private let completedKey = "zmanga_completed"
    private let cachedLatestKey = "zmanga_cached_latest"
    private let cachedPopularKey = "zmanga_cached_popular"
    private let mangaCacheKey = "zmanga_manga_cache"

    init() {
        loadHistory()
        loadLibrary()
        loadWantToRead()
        loadCompleted()
        loadCached()
        loadMangaCache()
    }

    // MARK: - History
    func saveProgress(_ progress: ReadingProgress) {
        history.removeAll { $0.mangaSlug == progress.mangaSlug }
        history.insert(progress, at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        persistHistory()
    }
    func clearHistory() { history.removeAll(); persistHistory() }
    private func persistHistory() { UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: historyKey) }
    private func loadHistory() { if let data = UserDefaults.standard.data(forKey: historyKey), let d = try? JSONDecoder().decode([ReadingProgress].self, from: data) { history = d } }

    // MARK: - Favorites
    func addToLibrary(_ manga: Manga) { guard !library.contains(where: { $0.slug == manga.slug }) else { return }; library.insert(manga, at: 0); persistLibrary() }
    func removeFromLibrary(_ manga: Manga) { library.removeAll { $0.slug == manga.slug }; persistLibrary() }
    func isInLibrary(_ manga: Manga) -> Bool { library.contains { $0.slug == manga.slug } }
    private func persistLibrary() { UserDefaults.standard.set(try? JSONEncoder().encode(library), forKey: libraryKey) }
    private func loadLibrary() { if let data = UserDefaults.standard.data(forKey: libraryKey), let d = try? JSONDecoder().decode([Manga].self, from: data) { library = d } }

    // MARK: - Want to Read
    func addWantToRead(_ manga: Manga) { guard !wantToRead.contains(where: { $0.slug == manga.slug }) else { return }; wantToRead.insert(manga, at: 0); persistWantToRead() }
    func removeWantToRead(_ manga: Manga) { wantToRead.removeAll { $0.slug == manga.slug }; persistWantToRead() }
    func isWantToRead(_ manga: Manga) -> Bool { wantToRead.contains { $0.slug == manga.slug } }
    private func persistWantToRead() { UserDefaults.standard.set(try? JSONEncoder().encode(wantToRead), forKey: wantToReadKey) }
    private func loadWantToRead() { if let data = UserDefaults.standard.data(forKey: wantToReadKey), let d = try? JSONDecoder().decode([Manga].self, from: data) { wantToRead = d } }

    // MARK: - Completed
    func addCompleted(_ manga: Manga) { guard !completed.contains(where: { $0.slug == manga.slug }) else { return }; completed.insert(manga, at: 0); persistCompleted() }
    func removeCompleted(_ manga: Manga) { completed.removeAll { $0.slug == manga.slug }; persistCompleted() }
    func isCompleted(_ manga: Manga) -> Bool { completed.contains { $0.slug == manga.slug } }
    private func persistCompleted() { UserDefaults.standard.set(try? JSONEncoder().encode(completed), forKey: completedKey) }
    private func loadCompleted() { if let data = UserDefaults.standard.data(forKey: completedKey), let d = try? JSONDecoder().decode([Manga].self, from: data) { completed = d } }

    // MARK: - Home Caching
    func saveCachedLatest(_ items: [Manga]) { cachedLatest = items; UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: cachedLatestKey) }
    func saveCachedPopular(_ items: [Manga]) { cachedPopular = items; UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: cachedPopularKey) }
    private func loadCached() {
        if let data = UserDefaults.standard.data(forKey: cachedLatestKey), let d = try? JSONDecoder().decode([Manga].self, from: data) { cachedLatest = d }
        if let data = UserDefaults.standard.data(forKey: cachedPopularKey), let d = try? JSONDecoder().decode([Manga].self, from: data) { cachedPopular = d }
    }

    // MARK: - Manga Detail Cache
    func cacheManga(_ manga: Manga) { mangaCache[manga.slug] = manga; persistMangaCache() }
    private func persistMangaCache() { UserDefaults.standard.set(try? JSONEncoder().encode(mangaCache), forKey: mangaCacheKey) }
    private func loadMangaCache() { if let data = UserDefaults.standard.data(forKey: mangaCacheKey), let d = try? JSONDecoder().decode([String: Manga].self, from: data) { mangaCache = d } }

    // MARK: - Cloudflare (مُعدّلة)
    func triggerCloudflare(url: URL) {
        activeChallenge = CloudflareChallenge(url: url)
    }
    func triggerReload() { reloadTrigger += 1 }
}

// MARK: - Design Tokens (النسخة العربية الذهبية)
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
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:  (a, r, g, b) = (255, (int>>8)*17, (int>>4 & 0xF)*17, (int & 0xF)*17)
        case 6:  (a, r, g, b) = (255, int>>16, int>>8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int>>24, int>>16 & 0xFF, int>>8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255,0,0,0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Cached Async Image (مع Referer ديناميكي وإعادة المحاولة)
struct CachedAsyncImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var attempt = 0

    private static let cache = URLCache(
        memoryCapacity: 80 * 1024 * 1024,
        diskCapacity: 400 * 1024 * 1024,
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    )

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else if isLoading && attempt < 3 {
                Rectangle()
                    .fill(Color(white: 0.12))
                    .overlay(ProgressView().tint(ZTheme.accent))
            } else {
                Rectangle()
                    .fill(Color(white: 0.12))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(ZTheme.textTertiary)
                    )
            }
        }
        .task(id: url?.absoluteString) {
            await MainActor.run {
                image = nil
                isLoading = true
                loadFailed = false
                attempt = 0
            }
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url else { isLoading = false; loadFailed = true; return }
        let urlStr = url.absoluteString.lowercased()
        if urlStr.contains("lekmanga.png") || urlStr.contains("-512.png") || urlStr.contains("/favicon") {
            isLoading = false; loadFailed = true; return
        }

        let config = URLSessionConfiguration.default
        config.urlCache = Self.cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: config)

        let wkCookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        for cookie in wkCookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }

        let allCookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let wkFiltered = wkCookies.filter { wk in !allCookies.contains(where: { $0.name == wk.name }) }
        let cookieHeader = (allCookies + wkFiltered)
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        // Referer ديناميكي يعتمد على host الفعلي للصورة
        let referer: String
        if let host = url.host {
            let components = host.components(separatedBy: ".")
            if components.count >= 2 {
                let mainDomain = components.suffix(2).joined(separator: ".")
                referer = "https://\(mainDomain)/"
            } else {
                referer = "https://\(host)/"
            }
        } else {
            referer = "https://lekmanga.site/"
        }

        for _ in 0..<3 {
            attempt += 1
            var request = URLRequest(url: url)
            request.setValue(referer, forHTTPHeaderField: "Referer")
            request.setValue("https://lekmanga.site", forHTTPHeaderField: "Origin")
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
            if !cookieHeader.isEmpty {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            do {
                let (data, response) = try await session.data(for: request)
                if let httpResp = response as? HTTPURLResponse,
                   httpResp.statusCode == 200,
                   let img = UIImage(data: data),
                   img.size.width > 0 {
                    await MainActor.run { image = img; isLoading = false }
                    return
                }
            } catch {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        await MainActor.run { loadFailed = true; isLoading = false }
    }
}