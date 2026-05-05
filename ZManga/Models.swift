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

    var isPlaceholder: Bool = false

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
         latestChapterNumber: String? = nil, lastUpdated: String? = nil,
         isPlaceholder: Bool = false) {
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
        self.isPlaceholder = isPlaceholder
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

// MARK: - Download Manager
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var downloads: [String: DownloadedChapter] = [:]
    @Published var activeDownloads: [String: Double] = [:] // slug:chapterSlug -> progress 0..1

    private let downloadsKey = "zmanga_downloads"

    init() { load() }

    struct DownloadedChapter: Codable, Identifiable {
        var id: String { "\(mangaSlug)_\(chapterSlug)" }
        let mangaSlug: String
        let chapterSlug: String
        let chapterNumber: String
        let mangaTitle: String
        let pages: [String] // local file paths
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
    func downloadChapter(manga: Manga, chapter: Chapter, pages: [String]) async {
        let key = "\(manga.slug)_\(chapter.slug)"
        guard !isDownloaded(mangaSlug: manga.slug, chapterSlug: chapter.slug),
              !isDownloading(mangaSlug: manga.slug, chapterSlug: chapter.slug) else { return }

        activeDownloads[key] = 0.0

        let dir = getChapterDir(mangaSlug: manga.slug, chapterSlug: chapter.slug)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var localPaths: [String] = []
        let session = URLSession.shared

        for (idx, urlStr) in pages.enumerated() {
            guard let url = URL(string: urlStr) else { continue }
            do {
                let (data, _) = try await session.data(from: url)
                let filePath = dir.appendingPathComponent("\(idx).jpg")
                try data.write(to: filePath)
                localPaths.append(filePath.path)
            } catch {
                localPaths.append(urlStr) // fallback to remote
            }
            activeDownloads[key] = Double(idx + 1) / Double(pages.count)
        }

        let downloaded = DownloadedChapter(
            mangaSlug: manga.slug,
            chapterSlug: chapter.slug,
            chapterNumber: chapter.number,
            mangaTitle: manga.title,
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

    func getPages(mangaSlug: String, chapterSlug: String) -> [String]? {
        downloads["\(mangaSlug)_\(chapterSlug)"]?.pages
    }

    private func getChapterDir(mangaSlug: String, chapterSlug: String) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("downloads/\(mangaSlug)/\(chapterSlug)")
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

    init() {
        loadHistory()
        loadLibrary()
    }

    func saveProgress(_ progress: ReadingProgress) {
        history.removeAll { $0.mangaSlug == progress.mangaSlug }
        history.insert(progress, at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        persistHistory()
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([ReadingProgress].self, from: data) else { return }
        history = decoded
    }

    func addToLibrary(_ manga: Manga) {
        guard !library.contains(where: { $0.slug == manga.slug }) else { return }
        library.insert(manga, at: 0)
        persistLibrary()
    }

    func removeFromLibrary(_ manga: Manga) {
        library.removeAll { $0.slug == manga.slug }
        persistLibrary()
    }

    func isInLibrary(_ manga: Manga) -> Bool {
        library.contains { $0.slug == manga.slug }
    }

    private func persistLibrary() {
        if let data = try? JSONEncoder().encode(library) {
            UserDefaults.standard.set(data, forKey: libraryKey)
        }
    }

    private func loadLibrary() {
        guard let data = UserDefaults.standard.data(forKey: libraryKey),
              let decoded = try? JSONDecoder().decode([Manga].self, from: data) else { return }
        library = decoded
    }

    func triggerCloudflare(url: URL) {
        cloudflareURL = url
        showCloudflareSheet = true
    }

    func triggerReload() {
        reloadTrigger += 1
    }
}

// MARK: - Design Tokens (مانجا بالعربي inspired)
struct ZTheme {
    // خلفيات
    static let bg       = Color(hex: "#0D0D0D")
    static let surface  = Color(hex: "#161616")
    static let card     = Color(hex: "#1C1C1C")
    static let cardHover = Color(hex: "#242424")

    // حدود
    static let border      = Color(hex: "#2A2A2A")
    static let borderLight = Color(hex: "#383838")

    // اللون الرئيسي: ذهبي/أصفر مثل مانجا بالعربي
    static let accent       = Color(hex: "#F5A623")
    static let accentBright = Color(hex: "#FFB940")
    static let accentDim    = Color(hex: "#F5A623").opacity(0.15)
    static let accentGlow   = Color(hex: "#F5A623").opacity(0.25)

    // نصوص
    static let textPrimary   = Color(hex: "#F0F0F0")
    static let textSecondary = Color(hex: "#8A8A8A")
    static let textTertiary  = Color(hex: "#4A4A4A")

    // حالات
    static let danger  = Color(hex: "#E85A6A")
    static let success = Color(hex: "#4CAF82")
    static let warning = Color(hex: "#F5A623")

    // تدرج خاص
    static let goldGradient = LinearGradient(
        colors: [Color(hex: "#F5A623"), Color(hex: "#E8850A")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:  (a, r, g, b) = (255, (int >> 8)*17, (int >> 4 & 0xF)*17, (int & 0xF)*17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Cached Async Image
struct CachedAsyncImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var retryCount = 0

    private static let cache = URLCache(
        memoryCapacity: 80 * 1024 * 1024,
        diskCapacity: 400 * 1024 * 1024,
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    )
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else if isLoading && !loadFailed {
                Rectangle()
                    .fill(ZTheme.card)
                    .overlay(
                        ProgressView()
                            .tint(ZTheme.accent)
                    )
            } else {
                Rectangle()
                    .fill(ZTheme.card)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundColor(ZTheme.textTertiary)
                            if retryCount < 2 {
                                Button("إعادة") {
                                    retryCount += 1
                                    loadFailed = false
                                    isLoading = true
                                    Task { await load() }
                                }
                                .font(.system(size: 10))
                                .foregroundColor(ZTheme.accent)
                            }
                        }
                    )
            }
        }
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        guard let url = url else {
            isLoading = false
            loadFailed = true
            return
        }

        // Try multiple URL variants
        let urlsToTry: [URL] = {
            var urls = [url]
            // Try without size suffix
            let patterns = ["-110x150", "-150x200", "-200x300", "-300x450", "-193x278"]
            for pattern in patterns {
                let cleaned = url.absoluteString.replacingOccurrences(of: pattern, with: "")
                if cleaned != url.absoluteString, let u = URL(string: cleaned) {
                    urls.append(u)
                }
            }
            return urls
        }()

        for tryURL in urlsToTry {
            do {
                var request = URLRequest(url: tryURL)
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
                request.setValue("https://lek-manga.net", forHTTPHeaderField: "Referer")
                let (data, response) = try await session.data(for: request)
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200,
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        image = uiImage
                        isLoading = false
                    }
                    return
                }
            } catch { }
        }

        await MainActor.run {
            loadFailed = true
            isLoading = false
        }
    }
}