import SwiftUI
import WebKit

// MARK: - Cloudflare Challenge Sheet
struct CloudflareSheet: View {
    @EnvironmentObject var store: AppStore
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                ZTheme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(ZTheme.accent.opacity(0.12))
                                .frame(width: 64, height: 64)
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(ZTheme.accent)
                        }
                        Text("Security Check")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ZTheme.textPrimary)
                        Text("Complete the verification below to continue")
                            .font(.system(size: 13))
                            .foregroundColor(ZTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                    .padding(.horizontal, 24)

                    Divider().background(ZTheme.border)

                    if let url = store.cloudflareURL {
                        CloudflareWebViewRepresentable(url: url) {
                            store.cookiesReady = true
                            store.showCloudflareSheet = false
                            store.triggerReload()
                            onDismiss()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        store.showCloudflareSheet = false
                    }
                    .foregroundColor(ZTheme.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // نسخ جميع الكوكيز فوراً
                        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                            for cookie in cookies {
                                HTTPCookieStorage.shared.setCookie(cookie)
                            }
                            DispatchQueue.main.async {
                                store.cookiesReady = true
                                store.showCloudflareSheet = false
                                store.triggerReload()
                                onDismiss()
                            }
                        }
                    }
                    .foregroundColor(ZTheme.accent)
                }
            }
        }
    }
}

// MARK: - WebView Representable
struct CloudflareWebViewRepresentable: UIViewRepresentable {
    let url: URL
    let onSuccess: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.backgroundColor = UIColor(ZTheme.bg)
        webView.scrollView.backgroundColor = UIColor(ZTheme.bg)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: CloudflareWebViewRepresentable
        private var hasCompleted = false
        private let originalURL: URL
        private var navigationCount = 0

        init(parent: CloudflareWebViewRepresentable) {
            self.parent = parent
            self.originalURL = parent.url
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigationCount += 1
            guard !hasCompleted else { return }

            if let currentURL = webView.url {
                if currentURL != originalURL,
                   !currentURL.absoluteString.contains("cdn-cgi/l/chk_jschl"),
                   navigationCount > 1 {
                    webView.evaluateJavaScript("document.title") { [weak self] result, _ in
                        guard let self = self, !self.hasCompleted else { return }
                        let title = result as? String ?? ""
                        let isCloudflare = title.contains("Just a moment") ||
                                           title.contains("Attention Required") ||
                                           title.contains("Checking your browser")
                        if !isCloudflare {
                            self.copyCookiesAndSucceed(webView)
                        }
                    }
                    return
                }

                webView.evaluateJavaScript("document.title") { [weak self] result, _ in
                    guard let self = self, !self.hasCompleted else { return }
                    let title = result as? String ?? ""
                    let isCloudflare = title.contains("Just a moment") ||
                                       title.contains("Attention Required") ||
                                       title.contains("Checking your browser")
                    if !isCloudflare && !title.isEmpty {
                        self.copyCookiesAndSucceed(webView)
                    }
                }
            }
        }

        private func copyCookiesAndSucceed(_ webView: WKWebView) {
            guard !hasCompleted else { return }
            hasCompleted = true
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                for cookie in cookies {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                DispatchQueue.main.async {
                    self.parent.onSuccess()
                }
            }
        }
    }
}