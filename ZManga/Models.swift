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

    init(slug: String, title: String, coverURL: String = "", genres: [String] = [],
         status: String = "", rating: String = "", description: String = "",
         chapters: [Chapter] = [], author: String = "", artist: String = "") {
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

// MARK: - Design Tokens
struct ZTheme {
    static let bg      = Color(hex: "#0F1117")
    static let surface = Color(hex: "#161B27")
    static let card    = Color(hex: "#1C2333")
    static let cardHover = Color(hex: "#212A3E")
    static let border  = Color(hex: "#2A3347")
    static let borderLight = Color(hex: "#334166")
    static let accent  = Color(hex: "#4F79D4")
    static let accentBright = Color(hex: "#6B93F0")
    static let accentDim = Color(hex: "#4F79D4").opacity(0.15)
    static let textPrimary   = Color(hex: "#E8ECF4")
    static let textSecondary = Color(hex: "#8895AA")
    static let textTertiary  = Color(hex: "#4A5568")
    static let danger  = Color(hex: "#E85A6A")
    static let success = Color(hex: "#4CAF82")
    static let warning = Color(hex: "#E8A84F")
    static let cardGradient = LinearGradient(
        colors: [Color(hex: "#1C2333"), Color(hex: "#161B27")],
        startPoint: .topLeading, endPoint: .bottomTrailing
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