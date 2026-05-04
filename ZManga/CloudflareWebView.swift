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
                            // إعادة تحميل البيانات تلقائياً بعد حل الـ challenge
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

        // Script أقوى: ينتظر اختفاء جميع علامات الـ challenge
        let script = """
        var _cfCheckCount = 0;
        var _cfInterval = setInterval(function() {
            _cfCheckCount++;
            var hasChallenge = (
                document.getElementById('cf-challenge-running') ||
                document.querySelector('.cf-browser-verification') ||
                document.querySelector('#challenge-running') ||
                document.querySelector('#challenge-form') ||
                document.title.indexOf('Just a moment') !== -1 ||
                document.title.indexOf('Attention Required') !== -1
            );
            if (!hasChallenge && document.readyState === 'complete' && _cfCheckCount > 2) {
                clearInterval(_cfInterval);
                window.webkit.messageHandlers.cloudflareDone.postMessage('done');
            }
            if (_cfCheckCount > 30) { clearInterval(_cfInterval); }
        }, 1500);
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
            // انتظر ثانية ثم تحقق من العنوان (أعطِ الـ JS وقت)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                webView.evaluateJavaScript("document.title") { [weak self] result, _ in
                    guard let self = self, !self.hasCompleted else { return }
                    if let title = result as? String,
                       !title.contains("Just a moment") &&
                       !title.contains("Attention Required") &&
                       !title.isEmpty &&
                       self.navigationCount > 1 {
                        self.transferCookiesAndDismiss(webView)
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "cloudflareDone", let webView = message.webView {
                // تأخير بسيط للتأكد من حفظ الـ cookies
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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