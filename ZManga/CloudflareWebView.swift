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
                // زر يدوي لإغلاق النافذة بعد إتمام التحدي
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // ينقل الكوكيز ثم يغلق ويعيد التحميل
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
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "cloudflareDone")

        // JavaScript محسّن: يراقب اختفاء عناصر التحدي عبر MutationObserver
        let script = """
        (function() {
            var hasCompleted = false;
            function checkAndFire() {
                if (hasCompleted) return;
                var challengeElements = document.querySelectorAll(
                    '#cf-challenge-running, .cf-browser-verification, #challenge-running, #challenge-form, [data-translate="complete_verification"]'
                );
                var isChallengeTitle = document.title.indexOf('Just a moment') !== -1 ||
                                       document.title.indexOf('Attention Required') !== -1 ||
                                       document.title.indexOf('Checking your browser') !== -1;
                if (challengeElements.length === 0 && !isChallengeTitle && document.readyState === 'complete') {
                    // انتظر قليلاً وتأكد مرة أخرى
                    setTimeout(function() {
                        challengeElements = document.querySelectorAll(
                            '#cf-challenge-running, .cf-browser-verification, #challenge-running, #challenge-form'
                        );
                        if (challengeElements.length === 0) {
                            hasCompleted = true;
                            window.webkit.messageHandlers.cloudflareDone.postMessage('done');
                        }
                    }, 1500);
                }
            }
            setInterval(checkAndFire, 2000);
            var observer = new MutationObserver(function() {
                checkAndFire();
            });
            observer.observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
        userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = userContentController
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.backgroundColor = UIColor(ZTheme.bg)
        webView.scrollView.backgroundColor = UIColor(ZTheme.bg)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url == nil {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            webView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSuccess: onSuccess)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onSuccess: () -> Void
        var hasCompleted = false
        var navigationCount = 0

        init(onSuccess: @escaping () -> Void) {
            self.onSuccess = onSuccess
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigationCount += 1
            // فحص إضافي بعد كل تحميل (احتياط)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self, !self.hasCompleted else { return }
                webView.evaluateJavaScript("document.title") { result, _ in
                    let title = result as? String ?? ""
                    let isCloudflare = title.contains("Just a moment") ||
                                       title.contains("Attention Required") ||
                                       title.contains("Checking your browser")
                    if !isCloudflare && !title.isEmpty && self.navigationCount > 1 {
                        self.transferCookiesAndDismiss(webView)
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "cloudflareDone", let webView = message.webView {
                // تأكيد ونقل الكوكيز
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.transferCookiesAndDismiss(webView)
                }
            }
        }

        private func transferCookiesAndDismiss(_ webView: WKWebView) {
            guard !hasCompleted else { return }
            hasCompleted = true
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                for cookie in cookies {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                DispatchQueue.main.async {
                    self.onSuccess()
                }
            }
        }
    }
}