import Foundation
import WebKit

// MARK: - MangaService
@MainActor
class MangaService: NSObject, ObservableObject {
    static let shared = MangaService()
    private let baseURL = "https://lekmanga.site"

    // WebView مخصص فقط لتحميل صفحات الفصول (lazy loading) ولتجاوز Cloudflare
    private var chapterWebView: WKWebView?

    private func getChapterWebView() -> WKWebView {
        if let wv = chapterWebView { return wv }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        self.chapterWebView = wv
        return wv
    }

    // MARK: - fetchHTML عبر URLSession مباشرة (أسرع بكثير من WKWebView)
    private func fetchHTML(urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        // نسخ كوكيز Cloudflare من WKWebView إلى URLSession
        let wkCookies: [HTTPCookie] = await withCheckedContinuation { cont in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
        for c in wkCookies { HTTPCookieStorage.shared.setCookie(c) }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://lekmanga.site", forHTTPHeaderField: "Referer")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("ar,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        // أرسل الكوكيز يدوياً
        let cookieHeader = (HTTPCookieStorage.shared.cookies(for: url) ?? [])
            .map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // إذا Cloudflare رجع 403 أو صفحة تحقق
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        let isCloudflare = httpResp.statusCode == 403 ||
            html.contains("Just a moment") ||
            html.contains("cf-browser-verification") ||
            html.contains("Checking your browser") ||
            html.contains("Attention Required")

        if isCloudflare {
            // نحتاج WKWebView لتجاوز Cloudflare
            let wvHTML = try await fetchHTMLViaWebView(url: url)
            if wvHTML.contains("Just a moment") || wvHTML.contains("Checking your browser") {
                AppStore.currentStore?.triggerCloudflare(url: url)
                throw ZMangaError.cloudflareChallenge
            }
            return wvHTML
        }

        return html
    }

    // MARK: - Navigation Delegate
    private class NavDelegate: NSObject, WKNavigationDelegate {
        var onFinish: (() -> Void)?
        var onError: ((Error) -> Void)?
        private var done = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !done else { return }
            done = true
            onFinish?()
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !done else { return }
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            done = true
            onError?(error)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            guard !done else { return }
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            done = true
            onError?(error)
        }
    }

    private func fetchHTMLViaWebView(url: URL) async throws -> String {
        let wv = getChapterWebView()
        wv.navigationDelegate = nil
        wv.stopLoading()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let nav = NavDelegate()
            nav.onFinish = {
                wv.navigationDelegate = nil
                wv.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                    if let html = result as? String {
                        cont.resume(returning: html)
                    } else {
                        cont.resume(throwing: error ?? URLError(.cannotDecodeContentData))
                    }
                }
            }
            nav.onError = { error in
                wv.navigationDelegate = nil
                cont.resume(throwing: error)
            }
            wv.navigationDelegate = nav
            objc_setAssociatedObject(wv, "navDelegate", nav, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            wv.load(req)
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
            .filter { manga in
                !manga.slug.isEmpty &&
                !manga.slug.contains("feed") &&
                !manga.coverURL.isEmpty &&
                !isLogoOnly(manga.coverURL) &&
                (manga.title.lowercased().contains(query.lowercased()) ||
                 manga.slug.lowercased().contains(query.lowercased()) ||
                 manga.genres.contains(where: { $0.lowercased().contains(query.lowercased()) }))
            }
    }

    func fetchDetail(slug: String) async throws -> Manga {
        let html = try await fetchHTML(urlString: "\(baseURL)/manga/\(slug)/")
        return parseMangaDetail(html: html, slug: slug)
    }

    func fetchChapterPages(mangaSlug: String, chapterSlug: String) async throws -> [String] {
        let urlString = "\(baseURL)/manga/\(mangaSlug)/\(chapterSlug)/"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        // 1. جلب HTML أولاً عبر URLSession للحصول على chapter_id
        let html = try await fetchHTML(urlString: urlString)

        // 2. محاولة AJAX (الأسرع) — لا يحتاج WKWebView
        let chapterIdPattern = #"(?:wp-manga-current-chap[^>]+data-id|data-id)="(\d+)""#
        if let chapterId = firstCapture(pattern: chapterIdPattern, in: html) {
            if let pages = try? await fetchChapterImagesViaAJAX(chapterId: chapterId), !pages.isEmpty {
                return pages
            }
        }

        // 3. محاولة parse مباشر من HTML الأولي
        let directPages = parseChapterPages(html: html)
        if !directPages.isEmpty { return directPages }

        // 4. آخر حل: WKWebView مع انتظار lazy loading
        let wv = getChapterWebView()
        wv.navigationDelegate = nil
        wv.stopLoading()

        // تحميل الصفحة في WKWebView وانتظار الـ lazy loading
        let finalHTML = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let nav = NavDelegate()
            nav.onFinish = {
                wv.navigationDelegate = nil
                // انتظر الـ lazy loading بعد didFinish
                let waitJS = """
                new Promise((resolve) => {
                    let tries = 0;
                    const check = () => {
                        tries++;
                        const imgs = document.querySelectorAll('.reading-content img');
                        const ok = Array.from(imgs).some(img => {
                            const s = img.dataset.lazySrc || img.dataset.src || img.src || '';
                            return s.startsWith('http') && !s.includes('data:image');
                        });
                        if (ok || tries >= 15) resolve(tries);
                        else setTimeout(check, 200);
                    };
                    setTimeout(check, 500);
                });
                """
                wv.evaluateJavaScript(waitJS) { _, _ in
                    wv.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                        if let html = result as? String {
                            cont.resume(returning: html)
                        } else {
                            cont.resume(throwing: error ?? URLError(.cannotDecodeContentData))
                        }
                    }
                }
            }
            nav.onError = { error in
                wv.navigationDelegate = nil
                cont.resume(throwing: error)
            }
            wv.navigationDelegate = nav
            objc_setAssociatedObject(wv, "navDelegate", nav, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            wv.load(req)
        }

        return parseChapterPages(html: finalHTML)
    }

    func fetchByGenre(genre: String, page: Int = 1) async throws -> [Manga] {
        let html = try await fetchHTML(urlString: "\(baseURL)/manga-genre/\(genre)/?page=\(page)")
        return parseMangaList(html: html, extractChapterInfo: false)
    }

    // MARK: - AJAX Image Fetching

    private func fetchChapterImagesViaAJAX(chapterId: String) async throws -> [String] {
        guard let ajaxURL = URL(string: "\(baseURL)/wp-admin/admin-ajax.php") else { return [] }

        var request = URLRequest(url: ajaxURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL, forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        // الكوكيز
        let wkCookies: [HTTPCookie] = await withCheckedContinuation { cont in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
        for c in wkCookies { HTTPCookieStorage.shared.setCookie(c) }
        let cookieHeader = (HTTPCookieStorage.shared.cookies(for: ajaxURL) ?? [])
            .map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        request.httpBody = "action=manga_get_chapter_img_list&chapter_id=\(chapterId)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { return [] }

        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr.compactMap { $0["url"] as? String }.filter { $0.hasPrefix("http") }
        }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let images = dict["data"] as? [[String: Any]] {
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
        let pattern = #"href="(https?://[^/]+/manga/([^/"]+)/)\"[^>]*>\s*(?:<[^>]+>\s*)*([^<]{3,})"#
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
                let linkPattern = #"href="(https?://[^/]+/manga/[^/]+/([^/]+)/)""#
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
            let chapLinkPattern = #"href="https?://[^/]+/manga/[^/]+/([\d]+(?:-[\d]+)?)/\"[^>]*>\s*(?:<[^>]*>\s*)*(\d+)"#
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

    // MARK: - Parse Chapter Pages (تجاهل صور الأغلفة)

    private func parseChapterPages(html: String) -> [String] {
        let content = extractReadingContent(html: html)
        var seen = Set<String>()
        var pages: [String] = []

        let allImgPattern = #"<img\s[^>]*>"#
        guard let imgRegex = try? NSRegularExpression(pattern: allImgPattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }

        let nsContent = content as NSString
        imgRegex.enumerateMatches(in: content, range: NSRange(location: 0, length: nsContent.length)) { match, _, _ in
            guard let match = match else { return }
            let tag = nsContent.substring(with: match.range)
            // تجاهل الصور التي لا تحمل أي من هذه السمات (صور أغلفة، أيقونات، إلخ)
            guard tag.contains("wp-manga-chapter-img") || tag.contains("data-src") || tag.contains("data-lazy-src") else { return }
            let url = firstCapture(pattern: #"data-lazy-src="([^"]+)""#, in: tag)
                   ?? firstCapture(pattern: #"data-src="([^"]+)""#, in: tag)
                   ?? firstCapture(pattern: #"\bsrc="([^"]+)""#, in: tag)
            if let url = url?.trimmingCharacters(in: .whitespacesAndNewlines),
               url.hasPrefix("http"),
               !url.contains("data:image"),
               !isLogoOnly(url),
               !seen.contains(url) {
                seen.insert(url)
                pages.append(url)
            }
        }
        return pages
    }

    private func extractReadingContent(html: String) -> String {
        let startPattern = #"<div[^>]+class="[^"]*reading-content[^"]*"[^>]*>"#
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
                depth += tag.hasPrefix("</") ? -1 : 1
                currentIndex = nextDiv.range.location + nextDiv.range.length
            } else { break }
        }
        if depth == 0 {
            let endLen = "</div>".count
            let cutAt = max(0, currentIndex - endLen)
            return nsRemaining.substring(to: cutAt)
        }
        return remaining
    }

    // MARK: - Image Helpers

    private func extractHTMLTags(named tagName: String, from html: String) -> [String] {
        let pattern = "<\(tagName)\\s[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private func extractImageURL(fromTags tags: [String]) -> String? {
        for tag in tags {
            if let url = firstCapture(pattern: #"data-lazy-src\s*=\s*"([^"]+)""#, in: tag),
               url.hasPrefix("http") { return url }
            if let url = firstCapture(pattern: #"data-src\s*=\s*"([^"]+)""#, in: tag),
               url.hasPrefix("http") { return url }
            if let url = firstCapture(pattern: #"src\s*=\s*"([^"]+)""#, in: tag),
               url.hasPrefix("http"), !isLogoOnly(url) { return url }
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