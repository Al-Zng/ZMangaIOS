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
        let url = "\(baseURL)/manga/\(mangaSlug)/\(chapterSlug)/"

        // 1. تحميل الصفحة أولاً للحصول على chapter_id
        let html = try await fetchHTML(urlString: url)

        // 2. محاولة AJAX أولاً (الأسرع والأموثق)
        if let chapterId = firstCapture(
            pattern: #"id="wp-manga-current-chap"[^>]+data-id="(\d+)""#,
            in: html
        ) {
            if let pages = try? await fetchChapterImagesViaAJAX(chapterId: chapterId), !pages.isEmpty {
                return pages
            }
        }

        // 3. الـ WebView محمّل بالفعل — الآن ننتظر حتى يُحقن lazy loading الصور في DOM
        let webView = getWebView()
        let waitJS = """
        new Promise((resolve) => {
            let attempts = 0;
            const check = () => {
                attempts++;
                const imgs = document.querySelectorAll('.reading-content img');
                const hasRealSrc = Array.from(imgs).some(img => {
                    const src = img.dataset.lazySrc || img.dataset.src || img.getAttribute('data-lazy-src') || img.src || '';
                    return src.startsWith('http') && !src.includes('data:image');
                });
                if (hasRealSrc || attempts >= 30) resolve(attempts);
                else setTimeout(check, 300);
            };
            // أعط الـ JS وقتاً ليبدأ
            setTimeout(check, 800);
        });
        """

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(waitJS) { _, _ in cont.resume() }
        }

        // 4. الآن اجلب الـ HTML بعد أن عمل الـ lazy loading
        let updatedHTML: String = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                if let html = result as? String {
                    continuation.resume(returning: html)
                } else {
                    continuation.resume(throwing: error ?? URLError(.cannotDecodeContentData))
                }
            }
        }

        let pages = parseChapterPages(html: updatedHTML)
        return pages
    }

    func fetchByGenre(genre: String, page: Int = 1) async throws -> [Manga] {
        let html = try await fetchHTML(urlString: "\(baseURL)/manga-genre/\(genre)/?page=\(page)")
        return parseMangaList(html: html, extractChapterInfo: false)
    }

    // MARK: - AJAX Image Fetching (الإصلاح الرئيسي)

    private func fetchChapterImagesViaAJAX(chapterId: String) async throws -> [String] {
        guard let ajaxURL = URL(string: "\(baseURL)/wp-admin/admin-ajax.php") else { return [] }

        var request = URLRequest(url: ajaxURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL, forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        // نسخ الكوكيز من WebView إلى الطلب
        let cookies = HTTPCookieStorage.shared.cookies(for: ajaxURL) ?? []
        let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let body = "action=manga_get_chapter_img_list&chapter_id=\(chapterId)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        // محاولة تفسير الـ response كـ JSON (مصفوفة أو كائن ببيانات)
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { $0["url"] as? String }.filter { $0.hasPrefix("http") }
        }
        if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let images = jsonDict["data"] as? [[String: Any]] {
            return images.compactMap { $0["url"] as? String }.filter { $0.hasPrefix("http") }
        }

        // إذا كان الـ response عبارة عن HTML (حالة نادرة)
        if let html = String(data: data, encoding: .utf8), html.contains("<img") {
            return parseChapterPages(html: html)
        }

        return []
    }



    // MARK: - Parse Manga List

    private func parseMangaList(html: String, extractChapterInfo: Bool) -> [Manga] {
        var results: [Manga] = []
        let cardPattern = #"<div class="page-item-detail[^"]*manga[^"]*">(.*?)</div>\s*</div>\s*</div>"#
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
        let title = firstCapture(pattern: #"<h3[^>]*>\s*<a[^>]*>([^<]+)</a>"#, in: block)
                 ?? firstCapture(pattern: #"<h5[^>]*>\s*<a[^>]*>([^<]+)</a>"#, in: block)
                 ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
        let allImgTags = extractHTMLTags(named: "img", from: block)
        let cover = extractImageURL(fromTags: allImgTags) ?? ""
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
                let allImgTags = extractHTMLTags(named: "img", from: html)
                let cover = extractImageURL(fromTags: allImgTags) ?? ""
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
        let summaryBlock = firstCapture(pattern: #"(<div class="summary_image[^"]*">.*?</div>)"#, in: html) ?? html
        let allImgTags = extractHTMLTags(named: "img", from: summaryBlock)
        let cover = extractImageURL(fromTags: allImgTags) ?? ""

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
        let chapterBlockPattern = #"<li class="wp-manga-chapter[^"]*">(.*?)</li>"#
        if let blockRegex = try? NSRegularExpression(pattern: chapterBlockPattern, options: [.dotMatchesLineSeparators]) {
            blockRegex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match = match, match.numberOfRanges >= 2 else { return }
                let block = ns.substring(with: match.range(at: 1))
                let linkPattern = #"href="(https?://[^/]+/manga/[^/]+/([^/]+)/)"#
                if let fullLink = firstCapture(pattern: linkPattern, in: block),
                   let url = URL(string: fullLink) {
                    let components = url.pathComponents
                    let slugPart = components.last(where: { !$0.isEmpty && $0 != "/" }) ?? ""
                    let numberPart = firstCapture(pattern: #">(\d+)</a>"#, in: block) ?? slugPart
                    let date = firstCapture(pattern: #"class="chapter-release-date"[^>]*>\s*(?:<[^>]+>)?([^<]+)<"#, in: block)
                    if !slugPart.isEmpty && !chapters.contains(where: { $0.slug == slugPart }) {
                        chapters.append(Chapter(slug: slugPart, number: numberPart, date: date?.trimmingCharacters(in: .whitespaces) ?? ""))
                    }
                }
            }
        }
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

    // MARK: - Parse Chapter Pages (يدعم data-lazy-src + استخراج محتوى reading-content)

    private func parseChapterPages(html: String) -> [String] {
        var pages: [String] = []
        let content = extractReadingContent(html: html)

        let patterns: [(String, NSRegularExpression.Options)] = [
            (#"<img[^>]+data-lazy-src="([^"]+)"[^>]*>"#, [.dotMatchesLineSeparators, .caseInsensitive]),
            (#"<img[^>]+data-src="([^"]+)"[^>]*class="[^"]*wp-manga-chapter-img[^"]*"[^>]*>"#, [.dotMatchesLineSeparators, .caseInsensitive]),
            (#"<img[^>]+class="[^"]*wp-manga-chapter-img[^"]*"[^>]*data-src="([^"]+)"[^>]*>"#, [.dotMatchesLineSeparators, .caseInsensitive]),
            (#"<img[^>]+src="([^"]+)"[^>]*class="[^"]*wp-manga-chapter-img[^"]*"[^>]*>"#, [.dotMatchesLineSeparators, .caseInsensitive]),
            (#"<img[^>]+class="[^"]*wp-manga-chapter-img[^"]*"[^>]*src="([^"]+)"[^>]*>"#, [.dotMatchesLineSeparators, .caseInsensitive]),
            (#"<img[^>]+(?:data-src|data-lazy-src|src)="([^"]+)"[^>]*>"#, [.dotMatchesLineSeparators, .caseInsensitive]),
        ]

        for (pattern, options) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            let c = content as NSString
            regex.enumerateMatches(in: content, range: NSRange(location: 0, length: c.length)) { match, _, _ in
                guard let match = match, match.numberOfRanges >= 2 else { return }
                let url = c.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if url.hasPrefix("http") && !isLogoOnly(url) && !pages.contains(url) {
                    pages.append(url)
                }
            }
            if !pages.isEmpty { break }
        }

        return pages
    }

    private func extractReadingContent(html: String) -> String {
        let startPattern = #"<div[^>]+class="[^"]*reading-content[^"]*"[^>]*>"#
        let endTag = "</div>"

        guard let startRegex = try? NSRegularExpression(pattern: startPattern, options: [.caseInsensitive]),
              let startMatch = startRegex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)) else {
            return html
        }

        let startIndex = startMatch.range.location + startMatch.range.length
        let remaining = (html as NSString).substring(from: startIndex)

        var depth = 1
        var currentIndex = 0
        let nsRemaining = remaining as NSString

        while currentIndex < nsRemaining.length && depth > 0 {
            let remainingRange = NSRange(location: currentIndex, length: nsRemaining.length - currentIndex)
            if let nextDiv = firstMatchOf(pattern: #"</?div"#, in: nsRemaining, range: remainingRange) {
                let tag = nsRemaining.substring(with: nextDiv.range)
                if tag.hasPrefix("</") {
                    depth -= 1
                } else {
                    depth += 1
                }
                currentIndex = nextDiv.range.location + nextDiv.range.length
            } else {
                break
            }
        }

        if depth == 0 {
            return nsRemaining.substring(to: currentIndex - endTag.count)
        }

        return remaining
    }

    // MARK: - دوال مساعدة لاستخراج الصور

    private func extractHTMLTags(named tagName: String, from html: String) -> [String] {
        let pattern = "<\(tagName)\\s[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
    }

    private func extractImageURL(fromTags tags: [String]) -> String? {
        for tag in tags {
            // data-lazy-src أولاً
            if let dataLazy = firstCapture(pattern: #"data-lazy-src\s*=\s*"([^"]+)""#, in: tag) {
                let url = dataLazy.trimmingCharacters(in: .whitespacesAndNewlines)
                if url.hasPrefix("http") { return url }
            }
            // data-src
            if let dataSrc = firstCapture(pattern: #"data-src\s*=\s*"([^"]+)""#, in: tag) {
                let url = dataSrc.trimmingCharacters(in: .whitespacesAndNewlines)
                if url.hasPrefix("http") { return url }
            }
            // src
            if let src = firstCapture(pattern: #"src\s*=\s*"([^"]+)""#, in: tag) {
                let url = src.trimmingCharacters(in: .whitespacesAndNewlines)
                if url.hasPrefix("http") && !isLogoOnly(url) { return url }
            }
        }
        return nil
    }

    private func firstMatchOf(pattern: String, in text: NSString, range: NSRange) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return regex.firstMatch(in: text as String, range: range)
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