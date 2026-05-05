import Foundation
import WebKit

// MARK: - MangaService
@MainActor
class MangaService: NSObject, ObservableObject {
    static let shared = MangaService()
    private let baseURL = "https://lek-manga.net"

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
        let url = "\(baseURL)/manga/?m_orderby=latest&page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html, extractChapterInfo: true)
    }

    func fetchPopular(page: Int = 1) async throws -> [Manga] {
        let url = "\(baseURL)/manga/?m_orderby=views&page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html, extractChapterInfo: false)
    }

    func search(query: String, page: Int = 1) async throws -> [Manga] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = "\(baseURL)/?s=\(encoded)&post_type=wp-manga&page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html, extractChapterInfo: false)
            .filter { !$0.slug.contains("feed") && !$0.slug.isEmpty }
    }

    func fetchDetail(slug: String) async throws -> Manga {
        let url = "\(baseURL)/manga/\(slug)/"
        let html = try await fetchHTML(urlString: url)
        return parseMangaDetail(html: html, slug: slug)
    }

    func fetchChapterPages(mangaSlug: String, chapterSlug: String) async throws -> [String] {
        let url = "\(baseURL)/manga/\(mangaSlug)/\(chapterSlug)/"
        let html = try await fetchHTML(urlString: url)
        return parseChapterPages(html: html)
    }

    func fetchByGenre(genre: String, page: Int = 1) async throws -> [Manga] {
        let url = "\(baseURL)/manga-genre/\(genre)/?page=\(page)"
        let html = try await fetchHTML(urlString: url)
        return parseMangaList(html: html, extractChapterInfo: false)
    }

    // MARK: - Parse Manga List

    private func parseMangaList(html: String, extractChapterInfo: Bool) -> [Manga] {
        var results: [Manga] = []
        let cardPattern = #"<div class="page-item-detail[^"]*">(.*?)</div>\s*</div>\s*</div>"#
        guard let cardRegex = try? NSRegularExpression(pattern: cardPattern, options: [.dotMatchesLineSeparators]) else { return results }
        let nsHtml = html as NSString
        let range = NSRange(location: 0, length: nsHtml.length)
        for match in cardRegex.matches(in: html, range: range).prefix(30) {
            let block = nsHtml.substring(with: match.range)
            if var manga = parseMangaCard(block) {
                if isLogoOnly(manga.coverURL) { continue }
                if extractChapterInfo {
                    let info = parseLatestChapterInfo(from: block)
                    manga.latestChapterNumber = info.chapter
                    manga.lastUpdated = info.time
                }
                results.append(manga)
            }
        }
        if results.isEmpty {
            results = parseMangaSimple(html: html, extractChapterInfo: extractChapterInfo)
        }
        return results
    }

    private func isLogoOnly(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("lekmanga.png") || lower.contains("-512.png") || lower.contains("/favicon")
    }

    // MARK: - FIX 1: استخراج صور البحث بشكل صحيح (data-src أولاً، ثم srcset، ثم src)
    private func parseMangaCard(_ block: String) -> Manga? {
        let hrefPattern = #"href="https?://[^/]+/manga/([^/"]+)/""#
        guard let slug = firstCapture(pattern: hrefPattern, in: block), !slug.isEmpty else { return nil }
        let titlePattern = #"<(?:h3|h4)[^>]*>\s*<a[^>]*>([^<]+)</a>"#
        let title = firstCapture(pattern: titlePattern, in: block) ?? slug.replacingOccurrences(of: "-", with: " ").capitalized

        // استخراج الصورة: جرب data-src أولاً، ثم srcset، ثم src
        let cover = extractBestImageURL(from: block)
        if slug.isEmpty || slug == "feed" || isLogoOnly(cover) { return nil }
        return Manga(slug: slug, title: htmlDecode(title), coverURL: cover)
    }

    /// يستخرج أفضل رابط صورة من block HTML بالترتيب: data-src > srcset > src
    private func extractBestImageURL(from block: String) -> String {
        // 1. data-src (lazy load)
        if let url = firstCapture(pattern: #"<img[^>]+data-src="([^"]+(?:\.jpg|\.jpeg|\.png|\.webp)[^"]*)"[^>]*>"#, in: block),
           !isLogoOnly(url) { return url }

        // 2. srcset - أخذ أول رابط فيه
        if let srcset = firstCapture(pattern: #"<img[^>]+srcset="([^"]+)"[^>]*>"#, in: block) {
            let parts = srcset.components(separatedBy: ",")
            for part in parts {
                let candidate = part.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
                if candidate.hasPrefix("http") && isValidImageURL(candidate) && !isLogoOnly(candidate) {
                    return candidate
                }
            }
        }

        // 3. src عادي
        if let url = firstCapture(pattern: #"<img[^>]+src="([^"]+(?:\.jpg|\.jpeg|\.png|\.webp)[^"]*)"[^>]*>"#, in: block),
           !isLogoOnly(url) { return url }

        return ""
    }

    private func parseMangaSimple(html: String, extractChapterInfo: Bool) -> [Manga] {
        var results: [Manga] = []
        let pattern = #"href="(https?://[^/]+/manga/([^/"]+)/)">?\s*(?:<[^>]+>\s*)*([^<]{3,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return results }
        let nsHtml = html as NSString
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: nsHtml.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 4 else { return }
            let slug = nsHtml.substring(with: match.range(at: 2))
            let rawTitle = nsHtml.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty, !rawTitle.isEmpty, rawTitle.count < 200,
                  slug != "feed", !slug.contains("cdn-cgi") else { return }
            if !results.contains(where: { $0.slug == slug }) {
                let cover = extractBestImageURL(from: html)
                var manga = Manga(slug: slug, title: htmlDecode(rawTitle), coverURL: isLogoOnly(cover) ? "" : cover)
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
        let chapter = firstCapture(pattern: #"<a[^>]+href="[^"]*chapter[^"]*"[^>]*>Chapter\s*([^<]+)</a>"#, in: block)
        let time = firstCapture(pattern: #"<span[^>]+class="[^"]*font-meta[^"]*"[^>]*>([^<]+)</span>"#, in: block)
        return (chapter?.trimmingCharacters(in: .whitespacesAndNewlines),
                time?.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Parse Manga Detail

    private func parseMangaDetail(html: String, slug: String) -> Manga {
        let title = firstCapture(pattern: #"<div class="post-title"[^>]*>\s*<h1[^>]*>\s*([^<]+)"#, in: html)
        let cover = firstCapture(pattern: #"class="summary_image"[^>]*>.*?<img[^>]+data-src="([^"]+)"#, in: html)
                 ?? firstCapture(pattern: #"class="summary_image"[^>]*>.*?<img[^>]+src="([^"]+)"#, in: html)
                 ?? ""
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
        if let genreRegex = try? NSRegularExpression(pattern: genrePattern) {
            let ns = html as NSString
            genreRegex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m = m, m.numberOfRanges >= 2 else { return }
                genres.append(ns.substring(with: m.range(at: 1)))
            }
        }

        // MARK: - FIX 2: استخراج slug الفصول بشكل صحيح (يدعم chapter-1 و chapter-1-5 وأرقام مباشرة)
        var chapters: [Chapter] = []

        // النمط الرئيسي: يلتقط الجزء الكامل بعد slug المانجا في الرابط
        let chapLinkPattern = #"href="https?://[^/]+/manga/[^/]+/([^/"]+)/"[^>]*>\s*(?:<[^>]*>\s*)*(?:Chapter|الفصل)\s*([\d.]+)"#
        if let chapRegex = try? NSRegularExpression(pattern: chapLinkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let ns = html as NSString
            chapRegex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m = m, m.numberOfRanges >= 3 else { return }
                let chapSlug = ns.substring(with: m.range(at: 1))
                let chapNum  = ns.substring(with: m.range(at: 2))
                if !chapSlug.isEmpty, !chapters.contains(where: { $0.slug == chapSlug }) {
                    chapters.append(Chapter(slug: chapSlug, number: chapNum))
                }
            }
        }

        // fallback: رقم عددي مباشر كـ slug
        if chapters.isEmpty {
            let fallbackPattern = #"href="https?://[^/]+/manga/[^/]+/(\d+(?:-\d+)?)/"[^>]*>"#
            if let fallbackRegex = try? NSRegularExpression(pattern: fallbackPattern, options: [.caseInsensitive]) {
                let ns = html as NSString
                fallbackRegex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                    guard let m = m, m.numberOfRanges >= 2 else { return }
                    let chapSlug = ns.substring(with: m.range(at: 1))
                    // استخراج الرقم من slug مثل "chapter-5" → "5"
                    let num = chapSlug.components(separatedBy: CharacterSet.decimalDigits.inverted)
                        .filter { !$0.isEmpty }.joined(separator: ".")
                    if !chapSlug.isEmpty, !chapters.contains(where: { $0.slug == chapSlug }) {
                        chapters.append(Chapter(slug: chapSlug, number: num.isEmpty ? chapSlug : num))
                    }
                }
            }
        }

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

    // MARK: - FIX 3: Parse Chapter Pages - يستخرج صور المانجا فقط من div القارئ
    private func parseChapterPages(html: String) -> [String] {
        var pages: [String] = []
        let ns = html as NSString

        // محاولة 1: البحث داخل div الخاص بالقارئ فقط
        let readerContainerPatterns = [
            #"<div[^>]+class="[^"]*reading-content[^"]*"[^>]*>(.*?)</div>\s*</div>"#,
            #"<div[^>]+class="[^"]*read-container[^"]*"[^>]*>(.*?)</div>\s*</div>"#,
            #"<div[^>]+id="[^"]*chapter-content[^"]*"[^>]*>(.*?)</div>"#,
        ]

        var readerBlock: String? = nil
        for pattern in readerContainerPatterns {
            if let block = firstCapture(pattern: pattern, in: html), block.count > 100 {
                readerBlock = block
                break
            }
        }

        let searchArea = readerBlock ?? html

        // محاولة 2: data-src أولاً (الصور lazy-loaded)
        let dataSrcPattern = #"<img[^>]+data-src="(https?://[^"]+\.(?:jpg|jpeg|png|webp)(?:\?[^"]*)?)"[^>]*>"#
        if let regex = try? NSRegularExpression(pattern: dataSrcPattern, options: [.caseInsensitive]) {
            let area = searchArea as NSString
            regex.enumerateMatches(in: searchArea, range: NSRange(location: 0, length: area.length)) { match, _, _ in
                guard let match = match, match.numberOfRanges >= 2 else { return }
                let url = area.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if isChapterImageURL(url) && !pages.contains(url) {
                    pages.append(url)
                }
            }
        }

        // محاولة 3: src عادي
        if pages.isEmpty {
            let srcPattern = #"<img[^>]+src="(https?://[^"]+\.(?:jpg|jpeg|png|webp)(?:\?[^"]*)?)"[^>]*>"#
            if let regex = try? NSRegularExpression(pattern: srcPattern, options: [.caseInsensitive]) {
                let area = searchArea as NSString
                regex.enumerateMatches(in: searchArea, range: NSRange(location: 0, length: area.length)) { match, _, _ in
                    guard let match = match, match.numberOfRanges >= 2 else { return }
                    let url = area.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if isChapterImageURL(url) && !pages.contains(url) {
                        pages.append(url)
                    }
                }
            }
        }

        // محاولة 4: fallback شامل على كل الـ HTML إذا ما لقينا شيء
        if pages.isEmpty {
            let fallbackPattern = #"(?:data-src|src)="(https?://[^"]+/(?:manga|uploads|content|chapter)[^"]+\.(?:jpg|jpeg|png|webp)(?:\?[^"]*)?)""#
            if let fRegex = try? NSRegularExpression(pattern: fallbackPattern, options: [.caseInsensitive]) {
                fRegex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                    guard let match = match, match.numberOfRanges >= 2 else { return }
                    let url = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if isChapterImageURL(url) && !pages.contains(url) {
                        pages.append(url)
                    }
                }
            }
        }

        return pages
    }

    /// تحقق أن الرابط هو صورة فصل حقيقية وليس أيقونة أو صورة UI
    private func isChapterImageURL(_ url: String) -> Bool {
        guard url.hasPrefix("http"), !url.contains("data:image") else { return false }
        let lower = url.lowercased()

        // استبعاد الأيقونات وصور الموقع
        let blockedKeywords = ["lekmanga.png", "-512.png", "/favicon", "logo", "banner",
                               "icon", "avatar", "gravatar", "placeholder", "ads", "ad-"]
        for keyword in blockedKeywords {
            if lower.contains(keyword) { return false }
        }

        // يجب أن يكون امتداد صورة
        guard lower.contains(".jpg") || lower.contains(".jpeg") ||
              lower.contains(".png") || lower.contains(".webp") else { return false }

        // يُفضّل أن يحتوي على مسار يدل على محتوى فصل
        return true
    }

    private func isValidImageURL(_ url: String) -> Bool {
        guard url.hasPrefix("http"), !url.contains("data:image") else { return false }
        let lower = url.lowercased()
        if lower.contains("lekmanga.png") || lower.contains("-512.png") || lower.contains("/favicon") { return false }
        return lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png") || lower.contains(".webp")
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