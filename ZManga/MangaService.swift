import Foundation
import WebKit

// MARK: - MangaService
@MainActor
class MangaService: NSObject, ObservableObject {
    static let shared = MangaService()
    private let baseURL = "https://lekmanga.site"

    // MARK: - جلب HTML الأساسي (مع كشف Cloudflare)
    private func fetchHTML(urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            Logger.shared.log("Bad URL: \(urlString)", category: "MangaService")
            throw URLError(.badURL)
        }
        Logger.shared.log("Fetching HTML: \(urlString)", category: "MangaService")

        return try await withCheckedThrowingContinuation { continuation in
            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.default()
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

            let nav = NavigationHandler(continuation: continuation)
            webView.navigationDelegate = nav
            // منع تحرير nav
            objc_setAssociatedObject(webView, "navHandler", nav, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            webView.load(request)
        }
    }

    // MARK: - وكيل الملاحة (للتقاط HTML ومعالجة Cloudflare)
    private class NavigationHandler: NSObject, WKNavigationDelegate {
        let continuation: CheckedContinuation<String, Error>

        init(continuation: CheckedContinuation<String, Error>) {
            self.continuation = continuation
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
                guard let self = self else { return }
                if let html = result as? String {
                    self.handleHTML(html, from: webView)
                } else {
                    self.continuation.resume(throwing: error ?? URLError(.cannotDecodeContentData))
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation.resume(throwing: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            continuation.resume(throwing: error)
        }

        private func handleHTML(_ html: String, from webView: WKWebView) {
            let isCloudflare = html.contains("Just a moment") ||
                               html.contains("cf-browser-verification") ||
                               html.contains("Checking your browser") ||
                               html.contains("Attention Required")

            Logger.shared.log("HTML Length: \(html.count)", category: "MangaService")
            Logger.shared.log("Cloudflare detected: \(isCloudflare)", category: "MangaService")

            if isCloudflare {
                if let url = webView.url {
                    Logger.shared.log("Triggering Cloudflare sheet for URL: \(url.absoluteString)", category: "MangaService")
                    DispatchQueue.main.async {
                        AppStore.currentStore?.triggerCloudflare(url: url)
                    }
                }
                // إتاحة فرصة للـ sheet للظهور ثم رمي الخطأ
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.continuation.resume(throwing: ZMangaError.cloudflareChallenge)
                }
            } else {
                continuation.resume(returning: html)
            }
        }
    }

    // MARK: - جلب صفحات الفصل (مع انتظار الصور البطيئة)
    private func fetchChapterHTMLWithLazyImages(urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        Logger.shared.log("Fetching chapter with lazy loading: \(urlString)", category: "ChapterPages")

        let html = try await fetchHTML(urlString: urlString)

        // إذا لم نجد chapter_id، نرجع HTML مباشرة
        guard firstCapture(pattern: #"id="wp-manga-current-chap"[^>]+data-id="(\d+)""#, in: html) != nil else {
            return html
        }

        // نصوص انتظار الصور
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
            setTimeout(check, 800);
        });
        """

        return try await withCheckedThrowingContinuation { continuation in
            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.default()
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

            let delegate = LazyDelegate(continuation: continuation, waitJS: waitJS)
            webView.navigationDelegate = delegate
            objc_setAssociatedObject(webView, "lazyDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            webView.load(request)
        }
    }

    // MARK: - Lazy Delegate (لا يحتاج إلى إغلاق خارجي)
    private class LazyDelegate: NSObject, WKNavigationDelegate {
        let continuation: CheckedContinuation<String, Error>
        let waitJS: String

        init(continuation: CheckedContinuation<String, Error>, waitJS: String) {
            self.continuation = continuation
            self.waitJS = waitJS
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(waitJS) { [weak self] _, _ in
                guard let self = self else { return }
                webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                    if let html = result as? String {
                        self.continuation.resume(returning: html)
                    } else {
                        self.continuation.resume(throwing: error ?? URLError(.cannotDecodeContentData))
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation.resume(throwing: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            continuation.resume(throwing: error)
        }
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
        Logger.shared.log("Fetching chapter pages: \(url)", category: "ChapterPages")

        let html = try await fetchHTML(urlString: url)

        // 1. محاولة AJAX أولاً
        if let chapterId = firstCapture(pattern: #"id="wp-manga-current-chap"[^>]+data-id="(\d+)""#, in: html) {
            Logger.shared.log("Chapter ID found: \(chapterId). Trying AJAX...", category: "ChapterPages")
            if let pages = try? await fetchChapterImagesViaAJAX(chapterId: chapterId), !pages.isEmpty {
                Logger.shared.log("AJAX success: \(pages.count) pages", category: "ChapterPages")
                return pages
            }
        }

        // 2. انتظار الصور البطيئة (lazy loading)
        Logger.shared.log("Attempting lazy image loading for chapter...", category: "ChapterPages")
        do {
            let updatedHTML = try await fetchChapterHTMLWithLazyImages(urlString: url)
            let pages = parseChapterPages(html: updatedHTML)
            Logger.shared.log("Lazy loading parsed \(pages.count) pages", category: "ChapterPages")
            return pages
        } catch {
            Logger.shared.log("Lazy loading failed: \(error.localizedDescription)", category: "ChapterPages")
            return parseChapterPages(html: html)
        }
    }

    func fetchByGenre(genre: String, page: Int = 1) async throws -> [Manga] {
        let html = try await fetchHTML(urlString: "\(baseURL)/manga-genre/\(genre)/?page=\(page)")
        return parseMangaList(html: html, extractChapterInfo: false)
    }

    // MARK: - AJAX Image Fetching

    private func fetchChapterImagesViaAJAX(chapterId: String) async throws -> [String] {
        guard let ajaxURL = URL(string: "\(baseURL)/wp-admin/admin-ajax.php") else { return [] }

        var request = URLRequest(url: ajaxURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL, forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let cookies = HTTPCookieStorage.shared.cookies(for: ajaxURL) ?? []
        let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let body = "action=manga_get_chapter_img_list&chapter_id=\(chapterId)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }

        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { $0["url"] as? String }.filter { $0.hasPrefix("http") }
        }
        if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let images = jsonDict["data"] as? [[String: Any]] {
            return images.compactMap { $0["url"] as? String }.filter { $0.hasPrefix("http") }
        }
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
                let searchRange = NSRange(location: match.range.location,
                                          length: min(nsHtml.length - match.range.location, 2000))
                let allImgTags = extractHTMLTags(named: "img", from: nsHtml.substring(with: searchRange))
                let cover = extractImageURL(fromTags: allImgTags) ?? ""
                var manga = Manga(slug: slug, title: htmlDecode(rawTitle), coverURL: isLogoOnly(cover) ? "" : cover)
                if extractChapterInfo {
                    let info = parseLatestChapterInfo(from: nsHtml.substring(with: searchRange))
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

    // MARK: - Parse Chapter Pages (مبسطة)
    private func parseChapterPages(html: String) -> [String] {
        var pages: [String] = []
        let content = extractReadingContent(html: html)

        let patterns: [String] = [
            #"<img[^>]+(?:data-src|data-lazy-src)\s*=\s*"([^"]+)""#,
            #"<img[^>]+src\s*=\s*"([^"]+)""#
        ]

        let nsContent = content as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            regex.enumerateMatches(in: content, range: NSRange(location: 0, length: nsContent.length)) { match, _, _ in
                guard let match = match, match.numberOfRanges >= 2 else { return }
                let url = nsContent.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if url.hasPrefix("http") &&
                   !url.contains("data:image") &&
                   !isLogoOnly(url) &&
                   !pages.contains(url) {
                    pages.append(url)
                }
            }
            if pages.count > 5 { break }
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

    // MARK: - مساعدات

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
            if let dataLazy = firstCapture(pattern: #"data-lazy-src\s*=\s*"([^"]+)""#, in: tag) {
                let url = dataLazy.trimmingCharacters(in: .whitespacesAndNewlines)
                if url.hasPrefix("http") { return url }
            }
            if let dataSrc = firstCapture(pattern: #"data-src\s*=\s*"([^"]+)""#, in: tag) {
                let url = dataSrc.trimmingCharacters(in: .whitespacesAndNewlines)
                if url.hasPrefix("http") { return url }
            }
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

// MARK: - الأخطاء المخصصة
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