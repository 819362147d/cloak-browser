import SwiftUI
import WebKit

struct ContentView: View {
    // Landing page: the detector itself, so the effect is visible at once.
    // Change to https://claude.ai for everyday use.
    private let startURL = URL(string: "https://ip.cx/")!

    var body: some View {
        WebView(url: startURL)
            .ignoresSafeArea(edges: .bottom)
    }
}

/// WKWebView wrapper that injects spoof.js at document start.
/// Everything the spoof does only applies INSIDE this app — iOS sandboxing
/// means Safari, the Claude app and every other app are unaffected.
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Incognito: non-persistent data store — cookies, localStorage,
        // cache and history are kept in memory only and wiped when the
        // app process ends. Nothing is written to the on-disk web store.
        // Trade-off: site logins do NOT survive an app restart.
        config.websiteDataStore = .nonPersistent()
        if let jsURL = Bundle.main.url(forResource: "spoof", withExtension: "js"),
           let js = try? String(contentsOf: jsURL, encoding: .utf8) {
            let script = WKUserScript(source: js,
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: false)
            config.userContentController.addUserScript(script)
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 " +
            "Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
