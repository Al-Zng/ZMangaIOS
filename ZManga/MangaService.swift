import Foundation
import WebKit

// MARK: - MangaService
@MainActor
class MangaService: NSObject, ObservableObject {
    static let shared = MangaService()
    private let baseURL = "https://lek-manga.net"

    private var webView: WKWebView?
    private var pendingContinuations: [CheckedContinuation<Void, Error>] = []

    private func getWebView() -> WKWebView {
        if let wv = webView { return wv }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
        self.webView = wv
        return wv
    }

    private func fetchHTML(urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let webView = getWebView()
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        webView.load(request)

        // انتظار انتهاء التحميل بشكل أكثر موثوقية
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var observer: NSKeyValueObservation?
            var didResume = false
            observer = webView.observe(\.isLoading, options: [.new]) { _, change in
                if change.newValue == false && !didResume {
                    didResume = true
                    observer?.invalidate()
                    // تأخير قصير للسماح بتحميل JS
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        continuation.resume()
                    }
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
           html.contains("Attention Required") ||
           html.contains("cf-challenge") {
            AppStore.currentStore?.triggerCloudflare(url: url)
            throw ZMangaError.cloudflareChallenge
        }

        return html
    }

    // MARK: - Fetch Latest
    func fetchLatest(page: Int = 1) async throws -> [Manga] {
        let url = "\(baseURL)/manga/?m_orderby=latest&page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html, extractChapterInfo: true)
    }

    // MARK: - Fetch Popular
    func fetchPopular(page: Int = 1) async throws -> [Manga] {
        let url = "\(baseURL)/manga/?m_orderby=views&page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html, extractChapterInfo: false)
    }

    // MARK: - Search
    func search(query: String, page: Int = 1) async throws -> [Manga] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = "\(baseURL)/?s=\(encoded)&post_type=wp-manga&page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html, extractChapterInfo: false)
            .filter { !$0.coverURL.isEmpty && !$0.slug.contains("feed") && !$0.slug.isEmpty }
    }

    // MARK: - Fetch Manga Detail
    func fetchDetail(slug: String) async throws -> Manga {
        let url = "\(baseURL)/manga/\(slug)/"
        let html = try await fetchHTML(urlString: url)
        return parseMangaDetail(html: html, slug: slug)
    }

    // MARK: - Fetch Chapter Pages (محسّن مع fallback متعدد)
    func fetchChapterPages(mangaSlug: String, chapterSlug: String) async throws -> [String] {
        // المسار القياسي
        let standardURL = "\(baseURL)/manga/\(mangaSlug)/\(chapterSlug)/"
        let html = try await fetchHTML(urlString: standardURL)

        var pages = parseChapterPages(html: html)

        // إذا فارغة، جرب المسار البديل
        if pages.isEmpty {
            let altURL = "\(baseURL)/\(mangaSlug)/\(chapterSlug)/"
            if let altHtml = try? await fetchHTML(urlString: altURL) {
                pages = parseChapterPages(html: altHtml)
            }
        }

        // جرب استخراج JSON من الصفحة
        if pages.isEmpty {
            pages = parseChapterPagesFromJSON(html: html)
        }

        return pages
    }

    // MARK: - Fetch by Genre
    func fetchByGenre(genre: String, page: Int = 1) async throws -> [Manga] {
        let url = "\(baseURL)/manga-genre/\(genre)/?page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html, extractChapterInfo: false)
    }

    // MARK: - Parse Manga List
    private func parseMangaList(html: String, extractChapterInfo: Bool) -> [Manga] {
        var results: [Manga] = []
        let cardPattern = #"<div class="page-item-detail[^"]*">(.*?)</div>\s*</div>\s*</div>"#
        let cardRegex = try? NSRegularExpression(pattern: cardPattern, options: [.dotMatchesLineSeparators])
        let nsHtml = html as NSString
        let range = NSRange(location: 0, length: nsHtml.length)
        if let matches = cardRegex?.matches(in: html, range: range) {
            for match in matches.prefix(30) {
                let block = nsHtml.substring(with: match.range)
                if var manga = parseMangaCard(block) {
                    if manga.coverURL.isEmpty { continue }
                    if extractChapterInfo {
                        let info = parseLatestChapterInfo(from: block)
                        manga.latestChapterNumber = info.chapter
                        manga.lastUpdated = info.time
                    }
                    results.append(manga)
                }
            }
        }
        if results.isEmpty {
            results = parseMangaSimple(html: html, extractChapterInfo: extractChapterInfo)
        }
        return results
    }

    private func parseMangaCard(_ block: String) -> Manga? {
        let hrefPattern = #"href="https?://[^/]+/manga/([^/"]+)/""#
        guard let slug = firstCapture(pattern: hrefPattern, in: block), !slug.isEmpty else { return nil }
        let titlePattern = #"<(?:h3|h4)[^>]*>\s*<a[^>]*>([^<]+)</a>"#
        let title = firstCapture(pattern: titlePattern, in: block) ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
        // محاولة استخراج data-src أولاً ثم src
        let coverPattern = #"<img[^>]+(?:data-src|src)="([^"]+(?:\.jpg|\.png|\.webp|\.jpeg)[^"]*)"[^>]*>"#
        let cover = firstCapture(pattern: coverPattern, in: block) ?? ""
        if slug.isEmpty || slug == "feed" { return nil }
        return Manga(slug: slug, title: htmlDecode(title), coverURL: cover)
    }

    private func parseMangaSimple(html: String, extractChapterInfo: Bool) -> [Manga] {
        var results: [Manga] = []
        let pattern = #"href="(https?://[^/]+/manga/([^/"]+)/)"[^>]*>\s*(?:<[^>]+>\s*)*([^<]{3,})"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsHtml = html as NSString
        regex?.enumerateMatches(in: html, range: NSRange(location: 0, length: nsHtml.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 4 else { return }
            let slug = nsHtml.substring(with: match.range(at: 2))
            let rawTitle = nsHtml.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty, !rawTitle.isEmpty, rawTitle.count < 200,
                  slug != "feed", !slug.contains("cdn-cgi") else { return }
            if !results.contains(where: { $0.slug == slug }) {
                var cover = ""
                let coverPattern = #"<img[^>]+(?:data-src|src)="([^"]+(?:\.jpg|\.png|\.webp|\.jpeg)[^"]*)"[^>]*>"#
                if let coverMatch = firstCapture(pattern: coverPattern, in: html) {
                    cover = coverMatch
                }
                var manga = Manga(slug: slug, title: htmlDecode(rawTitle), coverURL: cover)
                if extractChapterInfo {
                    let fullBlock = nsHtml.substring(with: match.range)
                    let info = parseLatestChapterInfo(from: fullBlock)
                    manga.latestChapterNumber = info.chapter
                    manga.lastUpdated = info.time
                }
                results.append(manga)
            }
        }
        return results
    }

    private func parseLatestChapterInfo(from block: String) -> (chapter: String?, time: String?) {
        // بحث موسّع عن رقم الفصل
        let chapPatterns = [
            #"<a[^>]+href="[^"]*chapter[^"]*"[^>]*>(?:الفصل|Chapter)\s*([^<\s]+)"#,
            #"<a[^>]+href="[^"]*chapter[^"]*"[^>]*>([^<]+)</a>"#,
            #"chapter-([\d]+(?:[\.\-][\d]+)?)"#
        ]
        var chapter: String? = nil
        for pattern in chapPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                if let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)) {
                    let raw = String(block[Range(match.range(at: 1), in: block)!]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !raw.isEmpty && raw.count < 20 {
                        chapter = raw
                        break
                    }
                }
            }
        }

        let timePattern = #"<span[^>]+class="[^"]*font-meta[^"]*"[^>]*>([^<]+)</span>"#
        var time: String? = nil
        if let regex = try? NSRegularExpression(pattern: timePattern, options: [.caseInsensitive]) {
            if let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)) {
                time = String(block[Range(match.range(at: 1), in: block)!]).trimmingCharacters(in: .whitespaces)
            }
        }
        return (chapter, time)
    }

    // MARK: - Parse Manga Detail (محسّن لاستخراج الفصول بشكل أدق)
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
        let status = firstCapture(pattern: #"<div class="summary-content">\s*(مستمرة|مكتملة|Ongoing|Completed|منتهية)\s*</div>"#, in: html) ?? ""
        let author = firstCapture(pattern: #"class="author-content">(.*?)</div>"#, in: html).map { stripHTML($0) } ?? ""

        var genres: [String] = []
        let genrePattern = #"/manga-genre/[^/]+/">([^<]+)</a>"#
        let genreRegex = try? NSRegularExpression(pattern: genrePattern)
        let ns = html as NSString
        genreRegex?.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 2 else { return }
            genres.append(ns.substring(with: m.range(at: 1)))
        }

        // استخراج الفصول بطرق متعددة مرتبة حسب الأولوية
        var chapters: [Chapter] = []

        // الطريقة 1: رابط الفصل مع الرقم والتاريخ (الأدق)
        let chapFullPattern = #"<li[^>]*class="[^"]*wp-manga-chapter[^"]*"[^>]*>(.*?)</li>"#
        if let regex = try? NSRegularExpression(pattern: chapFullPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
            regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m = m else { return }
                let block = ns.substring(with: m.range)
                // استخراج slug
                guard let chapSlug = firstCapture(pattern: #"href="https?://[^/]+/manga/[^/]+/([^/"]+)/""#, in: block),
                      !chapSlug.isEmpty else { return }
                // استخراج رقم الفصل
                let numPatterns = [
                    #"(?:الفصل|Chapter)\s*([\d]+(?:\.[\d]+)?)"#,
                    #"chapter-([\d]+(?:[\.\-][\d]+)?)"#,
                    #">([\d]+(?:\.[\d]+)?)<"#
                ]
                var chapNum = chapSlug
                for pattern in numPatterns {
                    if let n = firstCapture(pattern: pattern, in: block) ?? firstCapture(pattern: pattern, in: chapSlug) {
                        chapNum = n
                        break
                    }
                }
                // استخراج التاريخ
                let date = firstCapture(pattern: #"<span[^>]+class="[^"]*chapter-release-date[^"]*"[^>]*>.*?<[ia][^>]*>([^<]+)<"#, in: block) ?? ""

                if !chapters.contains(where: { $0.slug == chapSlug }) {
                    chapters.append(Chapter(slug: chapSlug, number: chapNum, date: date.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
        }

        // الطريقة 2: رابط مباشر إذا فشلت الأولى
        if chapters.isEmpty {
            let chapLinkPattern = #"href="https?://[^/]+/manga/[^/]+/([\w\d\-]+)/""#
            if let regex = try? NSRegularExpression(pattern: chapLinkPattern, options: [.caseInsensitive]) {
                regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                    guard let m = m, m.numberOfRanges >= 2 else { return }
                    let chapSlug = ns.substring(with: m.range(at: 1))
                    // تجاهل slugs غير الفصول
                    guard !chapSlug.isEmpty,
                          chapSlug != slug,
                          !chapSlug.contains("page"),
                          !chapSlug.contains("category") else { return }
                    // استخراج رقم من الـ slug
                    let numFromSlug = firstCapture(pattern: #"([\d]+(?:[\.\-][\d]+)?)$"#, in: chapSlug)
                        ?? firstCapture(pattern: #"([\d]+)"#, in: chapSlug)
                        ?? chapSlug
                    if !chapters.contains(where: { $0.slug == chapSlug }) {
                        chapters.append(Chapter(slug: chapSlug, number: numFromSlug))
                    }
                }
            }
        }

        // الطريقة 3: أرقام مباشرة في URL
        if chapters.isEmpty {
            let fallbackPattern = #"href="https?://[^/]+/manga/[^/]+/(\d+)/""#
            if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: [.caseInsensitive]) {
                regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                    guard let m = m, m.numberOfRanges >= 2 else { return }
                    let num = ns.substring(with: m.range(at: 1))
                    if !chapters.contains(where: { $0.slug == num }) {
                        chapters.append(Chapter(slug: num, number: num))
                    }
                }
            }
        }

        // ترتيب حسب الرقم
        chapters.sort { (Double($0.number) ?? 0) > (Double($1.number) ?? 0) }

        return Manga(slug: slug,
                     title: htmlDecode(title ?? slug.replacingOccurrences(of: "-", with: " ").capitalized),
                     coverURL: cover,
                     genres: genres,
                     status: status,
                     rating: rating,
                     description: description,
                     chapters: chapters,
                     author: author)
    }

    // MARK: - Parse Chapter Pages
    private func parseChapterPages(html: String) -> [String] {
        var pages: [String] = []
        let ns = html as NSString

        // الأنماط المختلفة لصور الفصول
        let patterns: [(String, NSRegularExpression.Options)] = [
            (#"<img[^>]*class="[^"]*wp-manga-chapter-img[^"]*"[^>]*data-src="([^"]+)"[^>]*>"#, [.dotMatchesLineSeparators, .caseInsensitive]),
            (#"<img[^>]*data-src="([^"]+)"[^>]*class="[^"]*wp-manga-chapter-img[^"]*"[^>]*>"#, [.dotMatchesLineSeparators, .caseInsensitive]),
            (#"<img[^>]*class="[^"]*wp-manga-chapter-img[^"]*"[^>]*src="([^"]+)"[^>]*>"#, [.dotMatchesLineSeparators, .caseInsensitive]),
            (#"<img[^>]*src="([^"]+)"[^>]*class="[^"]*wp-manga-chapter-img[^"]*"[^>]*>"#, [.dotMatchesLineSeparators, .caseInsensitive]),
            // نمط أوسع
            (#"class="[^"]*chapter-img[^"]*"[^>]*(?:src|data-src)="([^"]+)"#, [.dotMatchesLineSeparators, .caseInsensitive]),
            (#"(?:src|data-src)="([^"]+)"[^>]*class="[^"]*chapter-img[^"]*""#, [.dotMatchesLineSeparators, .caseInsensitive]),
        ]

        for (pattern, options) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                    if let match = match, match.numberOfRanges >= 2 {
                        let url = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if isValidImageURL(url) && !pages.contains(url) {
                            pages.append(url)
                        }
                    }
                }
            }
            if !pages.isEmpty { break }
        }

        return pages
    }

    // استخراج صور من JSON مضمّن
    private func parseChapterPagesFromJSON(html: String) -> [String] {
        var pages: [String] = []

        // بحث عن مصفوفة الصور في JSON مضمّن
        let jsonPatterns = [
            #"\"images\"\s*:\s*\[([^\]]+)\]"#,
            #"chapter_preloading_image\s*=\s*\[([^\]]+)\]"#,
            #"var\s+manga_chapter_images\s*=\s*\[([^\]]+)\]"#,
        ]

        let ns = html as NSString
        for pattern in jsonPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
                   match.numberOfRanges >= 2 {
                    let arrayStr = ns.substring(with: match.range(at: 1))
                    // استخراج URLs من المصفوفة
                    let urlPattern = #"\"(https?://[^"]+\.(?:jpg|jpeg|png|webp))\""#
                    if let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: [.caseInsensitive]) {
                        let urlNs = arrayStr as NSString
                        urlRegex.enumerateMatches(in: arrayStr, range: NSRange(location: 0, length: urlNs.length)) { m, _, _ in
                            if let m = m, m.numberOfRanges >= 2 {
                                let url = urlNs.substring(with: m.range(at: 1))
                                if !pages.contains(url) { pages.append(url) }
                            }
                        }
                    }
                    if !pages.isEmpty { break }
                }
            }
        }

        return pages
    }

    private func isValidImageURL(_ url: String) -> Bool {
        guard url.hasPrefix("http"), !url.contains("data:image") else { return false }
        let lower = url.lowercased()
        return lower.contains(".jpg") || lower.contains(".jpeg") ||
               lower.contains(".png") || lower.contains(".webp")
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
        case .cloudflareChallenge: return "مطلوب تحقق Cloudflare"
        case .parsingFailed: return "فشل تحليل المحتوى"
        case .networkError(let msg): return msg
        }
    }
}