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
                    // Header explanation
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

                    // WebView
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

    class Coordinator: NSObject, WKNavigationDelegate {
        let onSuccess: () -> Void
        private var successTimer: Timer?

        init(onSuccess: @escaping () -> Void) {
            self.onSuccess = onSuccess
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Check if we passed Cloudflare (page loaded normally)
            webView.evaluateJavaScript("document.title") { result, _ in
                let title = result as? String ?? ""
                let isCloudflare = title.contains("Just a moment") ||
                                   title.contains("Attention Required") ||
                                   title.contains("Checking your browser")
                if !isCloudflare {
                    // Copy cookies to HTTPCookieStorage
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

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Ignore cancellation errors
        }
    }
}
