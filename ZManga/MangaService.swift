import Foundation
import WebKit

// MARK: - MangaService
@MainActor
class MangaService: NSObject, ObservableObject {
    static let shared = MangaService()
    private let baseURL = "https://lekmanga.site"

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
        webView.load(request)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var observer: NSKeyValueObservation?
            observer = webView.observe(\.isLoading, options: [.new]) { _, change in
                if change.newValue == false {
                    observer?.invalidate()
                    continuation.resume()
                }
            }
        }

        let html: String = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                if let html = result as? String {
                    continuation.resume(returning: html)
                } else {
                    continuation.resume(throwing: error ?? URLError(.cannotDecodeContentData))
                }
            }
        }

        if html.contains("Just a moment") ||
           html.contains("cf-browser-verification") ||
           html.contains("Checking your browser") ||
           html.contains("Attention Required") {
            AppStore.currentStore?.triggerCloudflare(url: url)
            throw ZMangaError.cloudflareChallenge
        }

        return html
    }

    // MARK: - Public API

    func fetchLatest(page: Int = 1) async throws -> [Manga] {
        let html = try await fetchHTML(urlString: "\(baseURL)/manga/?m_orderby=latest&page=\(page)")
        return parseMangaList(html: html, extractChapterInfo: true)
    }

    func fetchPopular(page: Int = 1) async throws -> [Manga] {
        let html = try await fetchHTML(urlString: "\(baseURL)/manga/?m_orderby=views&page=\(page)")
        return parseMangaList(html: html, extractChapterInfo: false)
    }

    func search(query: String, page: Int = 1) async throws -> [Manga] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let html = try await fetchHTML(urlString: "\(baseURL)/?s=\(encoded)&post_type=wp-manga&page=\(page)")
        return parseMangaList(html: html, extractChapterInfo: false)
            .filter { !$0.slug.contains("feed") && !$0.slug.isEmpty && !$0.coverURL.isEmpty }
    }

    func fetchDetail(slug: String) async throws -> Manga {
        let html = try await fetchHTML(urlString: "\(baseURL)/manga/\(slug)/")
        return parseMangaDetail(html: html, slug: slug)
    }

    func fetchChapterPages(mangaSlug: String, chapterSlug: String) async throws -> [String] {
        let html = try await fetchHTML(urlString: "\(baseURL)/manga/\(mangaSlug)/\(chapterSlug)/")
        return parseChapterPages(html: html)
    }

    func fetchByGenre(genre: String, page: Int = 1) async throws -> [Manga] {
        let html = try await fetchHTML(urlString: "\(baseURL)/manga-genre/\(genre)/?page=\(page)")
        return parseMangaList(html: html, extractChapterInfo: false)
    }

    // MARK: - Parse Manga List

    private func parseMangaList(html: String, extractChapterInfo: Bool) -> [Manga] {
        var results: [Manga] = []
        let cardPattern = #"<div class="page-item-detail[^"]*">(.*?)</div>\s*</div>\s*</div>"#
        guard let cardRegex = try? NSRegularExpression(pattern: cardPattern, options: [.dotMatchesLineSeparators]) else { return results }
        let nsHtml = html as NSString
        for match in cardRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length)).prefix(30) {
            let block = nsHtml.substring(with: match.range)
            if var manga = parseMangaCard(block) {
                if manga.coverURL.isEmpty || isLogoOnly(manga.coverURL) { continue }
                if extractChapterInfo {
                    let info = parseLatestChapterInfo(from: block)
                    manga.latestChapterNumber = info.chapter
                    manga.lastUpdated = info.time
                }
                results.append(manga)
            }
        }
        if results.isEmpty { results = parseMangaSimple(html: html, extractChapterInfo: extractChapterInfo) }
        return results
    }

    private func isLogoOnly(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("lekmanga.png") || lower.contains("-512.png") || lower.contains("/favicon")
    }

    private func parseMangaCard(_ block: String) -> Manga? {
        guard let slug = firstCapture(pattern: #"href="https?://[^/]+/manga/([^/"]+)/""#, in: block), !slug.isEmpty else { return nil }
        let title = firstCapture(pattern: #"<(?:h3|h4)[^>]*>\s*<a[^>]*>([^<]+)</a>"#, in: block) ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
        let cover = firstCapture(pattern: #"<img[^>]+data-src="([^"]+(?:\.jpg|\.png|\.webp)[^"]*)"[^>]*>"#, in: block)
                 ?? firstCapture(pattern: #"<img[^>]+src="([^"]+(?:\.jpg|\.png|\.webp)[^"]*)"[^>]*>"#, in: block) ?? ""
        if slug.isEmpty || slug == "feed" || isLogoOnly(cover) { return nil }
        return Manga(slug: slug, title: htmlDecode(title), coverURL: cover)
    }

    private func parseMangaSimple(html: String, extractChapterInfo: Bool) -> [Manga] {
        var results: [Manga] = []
        let pattern = #"href="(https?://[^/]+/manga/([^/"]+)/)"[^>]*>\s*(?:<[^>]+>\s*)*([^<]{3,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return results }
        let nsHtml = html as NSString
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: nsHtml.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 4 else { return }
            let slug = nsHtml.substring(with: match.range(at: 2))
            let rawTitle = nsHtml.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty, !rawTitle.isEmpty, rawTitle.count < 200, slug != "feed", !slug.contains("cdn-cgi") else { return }
            if !results.contains(where: { $0.slug == slug }) {
                let cover = firstCapture(pattern: #"<img[^>]+data-src="([^"]+(?:\.jpg|\.png|\.webp)[^"]*)"[^>]*>"#, in: html)
                         ?? firstCapture(pattern: #"<img[^>]+src="([^"]+(?:\.jpg|\.png|\.webp)[^"]*)"[^>]*>"#, in: html) ?? ""
                var manga = Manga(slug: slug, title: htmlDecode(rawTitle), coverURL: isLogoOnly(cover) ? "" : cover)
                if extractChapterInfo {
                    let info = parseLatestChapterInfo(from: nsHtml.substring(with: match.range))
                    manga.latestChapterNumber = info.chapter; manga.lastUpdated = info.time
                }
                results.append(manga)
            }
        }
        return results
    }

    private func parseLatestChapterInfo(from block: String) -> (chapter: String?, time: String?) {
        let chapter = firstCapture(pattern: #"<a[^>]+href="[^"]*chapter[^"]*"[^>]*>Chapter\s*([^<]+)</a>"#, in: block)
        let time = firstCapture(pattern: #"<span[^>]+class="[^"]*font-meta[^"]*"[^>]*>([^<]+)</span>"#, in: block)
        return (chapter?.trimmingCharacters(in: .whitespacesAndNewlines),
                time?.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Parse Manga Detail

    private func parseMangaDetail(html: String, slug: String) -> Manga {
        let title = firstCapture(pattern: #"<div class="post-title"[^>]*>\s*<h1[^>]*>\s*([^<]+)"#, in: html)
        let cover = firstCapture(pattern: #"class="summary_image"[^>]*>.*?<img[^>]+data-src="([^"]+)"#, in: html)
                 ?? firstCapture(pattern: #"class="summary_image"[^>]*>.*?<img[^>]+src="([^"]+)"#, in: html) ?? ""
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
        let genreRegex = try? NSRegularExpression(pattern: #"/manga-genre/[^/]+/">([^<]+)</a>"#)
        let ns = html as NSString
        genreRegex?.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 2 else { return }
            genres.append(ns.substring(with: m.range(at: 1)))
        }

        var chapters: [Chapter] = []
        // استخراج الفصول من li.wp-manga-chapter
        let chapterBlockPattern = #"<li class="wp-manga-chapter[^"]*">(.*?)</li>"#
        if let blockRegex = try? NSRegularExpression(pattern: chapterBlockPattern, options: [.dotMatchesLineSeparators]) {
            blockRegex.enumerateMatches(in: html, range: NSRange(location: 0, length: (html as NSString).length)) { match, _, _ in
                guard let match = match, match.numberOfRanges >= 2 else { return }
                let block = (html as NSString).substring(with: match.range(at: 1))
                if let fullUrl = firstCapture(pattern: #"href="(https?://[^/]+/manga/[^/]+/([^/"]+)/)""#, in: block) {
                    var slugPart = ""
                    var numberPart = ""
                    if let url = URL(string: fullUrl) {
                        let components = url.pathComponents
                        slugPart = components.last ?? fullUrl
                        numberPart = components.last ?? fullUrl
                    }
                    let numberFromText = firstCapture(pattern: #">(\d+)</a>"#, in: block)
                    if let num = numberFromText { numberPart = num }
                    if !slugPart.isEmpty && !chapters.contains(where: { $0.slug == slugPart }) {
                        chapters.append(Chapter(slug: slugPart, number: numberPart))
                    }
                }
            }
        }
        // fallback
        if chapters.isEmpty {
            let chapLinkPattern = #"href="https?://[^/]+/manga/[^/]+/([\d]+(?:-[\d]+)?)/"[^>]*>\s*(?:<[^>]*>\s*)*(\d+)"#
            if let regex = try? NSRegularExpression(pattern: chapLinkPattern, options: [.caseInsensitive]) {
                regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                    guard let m = m, m.numberOfRanges >= 3 else { return }
                    let s = ns.substring(with: m.range(at: 1))
                    let n = ns.substring(with: m.range(at: 2))
                    if !chapters.contains(where: { $0.slug == s }) { chapters.append(Chapter(slug: s, number: n)) }
                }
            }
        }
        chapters.sort { (Int($0.number) ?? 0) > (Int($1.number) ?? 0) }

        return Manga(slug: slug,
                     title: htmlDecode(title ?? slug.replacingOccurrences(of: "-", with: " ").capitalized),
                     coverURL: cover, genres: genres, status: status, rating: rating,
                     description: description, chapters: chapters, author: author)
    }

// MARK: - Parse Chapter Pages (نسخة شاملة لجميع الهياكل)

private func parseChapterPages(html: String) -> [String] {
    var pages: [String] = []
    let ns = html as NSString

    // الخطوة 1: استخراج كل روابط الصور من الصفحة (src و data-src)
    var allImageURLs: [String] = []
    let imgTagPattern = #"<img[^>]+(?:src|data-src)\s*=\s*"([^"]+)"[^>]*>"#
    if let imgRegex = try? NSRegularExpression(pattern: imgTagPattern,
                                               options: [.dotMatchesLineSeparators, .caseInsensitive]) {
        imgRegex.enumerateMatches(in: html,
                                  range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            let url = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !allImageURLs.contains(url) {
                allImageURLs.append(url)
            }
        }
    }

    // الخطوة 2: فلترة الروابط
    for url in allImageURLs {
        if isValidChapterImageURL(url) && !pages.contains(url) {
            pages.append(url)
        }
    }

    // الخطوة 3: نمط احتياطي أوسع
    if pages.isEmpty {
        let fallbackPattern = #"(?:src|data-src)\s*=\s*"([^"]+\.(?:jpg|jpeg|png|webp))""#
        if let fbRegex = try? NSRegularExpression(pattern: fallbackPattern,
                                                  options: [.caseInsensitive]) {
            fbRegex.enumerateMatches(in: html,
                                     range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match = match, match.numberOfRanges >= 2 else { return }
                let url = ns.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidChapterImageURL(url) && !pages.contains(url) {
                    pages.append(url)
                }
            }
        }
    }

    return pages
}

// دالة مساعدة للتحقق من صلاحية رابط صورة الفصل
private func isValidChapterImageURL(_ url: String) -> Bool {
    guard url.hasPrefix("http"), !url.contains("data:image") else { return false }
    let lower = url.lowercased()

    // استبعاد الشعارات والأيقونات
    if lower.contains("lekmanga.png") ||
       lower.contains("-512.png") ||
       lower.contains("-192x192.png") ||
       lower.contains("-32x32.png") ||
       lower.contains("-150x150.png") ||
       lower.contains("/favicon") ||
       lower.contains("logo") ||
       lower.contains("/icon-") {
        return false
    }

    // استبعاد الصور الوهمية
    if lower.contains("-1x1") || lower.contains("blank") || lower.contains("placeholder") {
        return false
    }

    // يجب أن ينتهي بامتداد صورة معروف
    let validExtensions = [".jpg", ".jpeg", ".png", ".webp"]
    return validExtensions.contains(where: { lower.hasSuffix($0) || lower.contains($0 + "?") })
}

    // MARK: - Helpers

    private func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges >= 2 else { return nil }
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