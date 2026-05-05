import Foundation
import WebKit

// MARK: - MangaService
@MainActor
class MangaService: NSObject, ObservableObject {
    static let shared = MangaService()
    private let baseURL = "https://lek-manga.net"

    // MARK: - WebView for fetching (runs on main thread)
    private var webView: WKWebView?

    private func getWebView() -> WKWebView {
        if let wv = webView { return wv }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        self.webView = wv
        return wv
    }

    private func fetchHTML(urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let webView = getWebView()
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // تحميل الصفحة على الـ main thread
        webView.load(request)

        // انتظار انتهاء التحميل
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var observer: NSKeyValueObservation?
            observer = webView.observe(\.isLoading, options: [.new]) { _, change in
                if change.newValue == false {
                    observer?.invalidate()
                    continuation.resume()
                }
            }
        }

        // استخراج HTML
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                if let html = result as? String {
                    continuation.resume(returning: html)
                } else {
                    continuation.resume(throwing: error ?? URLError(.cannotDecodeContentData))
                }
            }
        }
    }

    // MARK: - Fetch Latest Manga
    func fetchLatest(page: Int = 1) async throws -> [Manga] {
        let url = "\(baseURL)/manga/?m_orderby=latest&page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html)
    }

    // MARK: - Fetch Popular
    func fetchPopular(page: Int = 1) async throws -> [Manga] {
        let url = "\(baseURL)/manga/?m_orderby=views&page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html)
    }

    // MARK: - Search
    func search(query: String, page: Int = 1) async throws -> [Manga] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = "\(baseURL)/?s=\(encoded)&post_type=wp-manga&page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html)
    }

    // MARK: - Fetch Manga Detail
    func fetchDetail(slug: String) async throws -> Manga {
        let url = "\(baseURL)/manga/\(slug)/"
        let html = try await fetchHTML(urlString: url)
        return parseMangaDetail(html: html, slug: slug)
    }

    // MARK: - Fetch Chapter Pages
    func fetchChapterPages(mangaSlug: String, chapterSlug: String) async throws -> [String] {
        let url = "\(baseURL)/manga/\(mangaSlug)/\(chapterSlug)/"
        let html = try await fetchHTML(urlString: url)
        return parseChapterPages(html: html)
    }

    // MARK: - Fetch by Genre
    func fetchByGenre(genre: String, page: Int = 1) async throws -> [Manga] {
        let url = "\(baseURL)/manga-genre/\(genre)/?page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html)
    }

    // MARK: - Parse Manga List
    private func parseMangaList(html: String) -> [Manga] {
        var results: [Manga] = []
        let cardPattern = #"<div class="page-item-detail[^"]*">(.*?)</div>\s*</div>\s*</div>"#
        let cardRegex = try? NSRegularExpression(pattern: cardPattern, options: [.dotMatchesLineSeparators])
        let nsHtml = html as NSString
        let range = NSRange(location: 0, length: nsHtml.length)
        if let matches = cardRegex?.matches(in: html, range: range) {
            for match in matches.prefix(30) {
                let block = nsHtml.substring(with: match.range)
                if let manga = parseMangaCard(block) {
                    results.append(manga)
                }
            }
        }
        if results.isEmpty {
            results = parseMangaSimple(html: html)
        }
        return results
    }

    private func parseMangaCard(_ block: String) -> Manga? {
        let hrefPattern = #"href="https?://[^/]+/manga/([^/"]+)/""#
        guard let slug = firstCapture(pattern: hrefPattern, in: block), !slug.isEmpty else { return nil }
        let titlePattern = #"<(?:h3|h4)[^>]*>\s*<a[^>]*>([^<]+)</a>"#
        let title = firstCapture(pattern: titlePattern, in: block) ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
        let coverPattern = #"<img[^>]+(?:src|data-src)="([^"]+(?:\.jpg|\.png|\.webp)[^"]*)"[^>]*>"#
        let cover = firstCapture(pattern: coverPattern, in: block) ?? ""
        return Manga(slug: slug, title: htmlDecode(title), coverURL: cover)
    }

    private func parseMangaSimple(html: String) -> [Manga] {
        var results: [Manga] = []
        let pattern = #"href="(https?://[^/]+/manga/([^/"]+)/)"[^>]*>\s*(?:<[^>]+>\s*)*([^<]{3,})"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsHtml = html as NSString
        regex?.enumerateMatches(in: html, range: NSRange(location: 0, length: nsHtml.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 4 else { return }
            let slug = nsHtml.substring(with: match.range(at: 2))
            let rawTitle = nsHtml.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty, !rawTitle.isEmpty, rawTitle.count < 200 else { return }
            if !results.contains(where: { $0.slug == slug }) {
                results.append(Manga(slug: slug, title: htmlDecode(rawTitle)))
            }
        }
        return results
    }

    // MARK: - Parse Manga Detail
    private func parseMangaDetail(html: String, slug: String) -> Manga {
        let title = firstCapture(pattern: #"<div class="post-title"[^>]*>\s*<h1[^>]*>\s*([^<]+)"#, in: html)
        let cover = firstCapture(pattern: #"class="summary_image"[^>]*>.*?<img[^>]+(?:src|data-src)="([^"]+)"#, in: html) ?? ""
        let description: String = {
            if let raw = firstCapture(pattern: #"<div class="summary__content[^"]*">(.*?)</div>"#, in: html) {
                return stripHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ""
        }()
        let rating = firstCapture(pattern: #"id="averagerate"[^>]*>([^<]+)<"#, in: html) ?? ""
        let status = firstCapture(pattern: #"<div class="summary-content">\s*(مستمرة|مكتملة|Ongoing|Completed)\s*</div>"#, in: html) ?? ""
        let author = firstCapture(pattern: #"class="author-content">(.*?)</div>"#, in: html).map { stripHTML($0) } ?? ""

        var genres: [String] = []
        let genrePattern = #"/manga-genre/[^/]+/">([^<]+)</a>"#
        let genreRegex = try? NSRegularExpression(pattern: genrePattern)
        let ns = html as NSString
        genreRegex?.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 2 else { return }
            genres.append(ns.substring(with: m.range(at: 1)))
        }

        var chapters: [Chapter] = []
        let chapLinkPattern = #"href="https?://[^/]+/manga/[^/]+/([\d]+(?:-[\d]+)?)/"[^>]*>\s*(?:<[^>]*>\s*)*(\d+)"#
        let chapRegex = try? NSRegularExpression(pattern: chapLinkPattern)
        chapRegex?.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 3 else { return }
            let chapSlug = ns.substring(with: m.range(at: 1))
            let chapNum = ns.substring(with: m.range(at: 2))
            if !chapters.contains(where: { $0.slug == chapSlug }) {
                chapters.append(Chapter(slug: chapSlug, number: chapNum))
            }
        }
        if chapters.isEmpty {
            let fallbackPattern = #"href="https?://[^/]+/manga/[^/]+/(\d+)/""#
            let fallbackRegex = try? NSRegularExpression(pattern: fallbackPattern)
            fallbackRegex?.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m = m, m.numberOfRanges >= 2 else { return }
                let num = ns.substring(with: m.range(at: 1))
                if !chapters.contains(where: { $0.slug == num }) {
                    chapters.append(Chapter(slug: num, number: num))
                }
            }
        }
        chapters.sort { (Int($0.number) ?? 0) > (Int($1.number) ?? 0) }

        return Manga(slug: slug, title: htmlDecode(title ?? slug.replacingOccurrences(of: "-", with: " ").capitalized),
                     coverURL: cover, genres: genres, status: status, rating: rating,
                     description: description, chapters: chapters, author: author)
    }

    // MARK: - Parse Chapter Pages
    private func parseChapterPages(html: String) -> [String] {
        var pages: [String] = []
        let pattern = #"<img[^>]*class="[^"]*wp-manga-chapter-img[^"]*"[^>]*src="([^"]+)"[^>]*>"#
        let ns = html as NSString
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                if let match = match, match.numberOfRanges >= 2 {
                    let url = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !pages.contains(url) { pages.append(url) }
                }
            }
        }
        if pages.isEmpty {
            let fallbackPattern = #"<img[^>]+class="[^"]*wp-manga-chapter-img[^"]*"[^>]+(?:src|data-src)="([^"]+)""#
            if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: [.dotMatchesLineSeparators]) {
                regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                    if let match = match, match.numberOfRanges >= 2 {
                        let url = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !pages.contains(url) { pages.append(url) }
                    }
                }
            }
        }
        return pages
    }

    // MARK: - Helpers
    private func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        let r = m.range(at: 1)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r)
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func htmlDecode(_ str: String) -> String {
        str.replacingOccurrences(of: "&amp;", with: "&")
           .replacingOccurrences(of: "&lt;", with: "<")
           .replacingOccurrences(of: "&gt;", with: ">")
           .replacingOccurrences(of: "&quot;", with: "\"")
           .replacingOccurrences(of: "&#039;", with: "'")
           .replacingOccurrences(of: "&nbsp;", with: " ")
           .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ZMangaError: LocalizedError {
    case cloudflareChallenge
    case parsingFailed
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .cloudflareChallenge: return "Cloudflare verification required"
        case .parsingFailed: return "Failed to parse content"
        case .networkError(let msg): return msg
        }
    }
}