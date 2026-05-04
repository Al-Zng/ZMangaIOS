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
                    VStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(ZTheme.accent)
                        Text("Security Check")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(ZTheme.textPrimary)
                        Text("Complete the verification below to continue")
                            .font(.system(size: 13))
                            .foregroundColor(ZTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 24)

                    Divider().background(ZTheme.border)

                    if let url = store.cloudflareURL {
                        CloudflareWebViewRepresentable(url: url) {
                            store.cookiesReady = true
                            store.showCloudflareSheet = false
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
        // إضافة مُعالج رسائل من JavaScript
        userContentController.add(context.coordinator, name: "cloudflareDone")
        // JavaScript يراقب اختفاء تحدي Cloudflare ويُعلم التطبيق
        let script = """
        setInterval(function() {
            if (!document.getElementById('cf-challenge-running') &&
                !document.querySelector('.cf-browser-verification') &&
                document.readyState === 'complete' &&
                document.title.indexOf('Just a moment') === -1) {
                window.webkit.messageHandlers.cloudflareDone.postMessage('done');
            }
        }, 1000);
        """
        userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = userContentController
        config.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
        webView.backgroundColor = UIColor(ZTheme.bg)
        webView.scrollView.backgroundColor = UIColor(ZTheme.bg)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url == nil {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSuccess: onSuccess)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onSuccess: () -> Void
        var hasCompleted = false

        init(onSuccess: @escaping () -> Void) {
            self.onSuccess = onSuccess
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // فحص إضافي عن طريق JavaScript بشكل فوري
            webView.evaluateJavaScript("document.title") { result, _ in
                if let title = result as? String,
                   !title.contains("Just a moment") && !title.contains("Attention Required") {
                    self.transferCookiesAndDismiss(webView)
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "cloudflareDone", let webView = message.webView {
                transferCookiesAndDismiss(webView)
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