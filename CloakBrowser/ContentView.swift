import SwiftUI
import WebKit

struct ContentView: View {
    @StateObject private var store = WebViewStore()
    @State private var input = "https://ip.cx/"

    var body: some View {
        VStack(spacing: 0) {
            // Address / search bar
            HStack(spacing: 8) {
                TextField("输入网址或搜索关键词", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.go)
                    .onSubmit { store.load(input) }
                Button {
                    store.load(input)
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .imageScale(.large)
                }
            }
            .padding(8)

            WebView(store: store)

            // Toolbar: back / forward / reload-or-stop / home / detector
            HStack {
                Button { store.webView.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!store.canGoBack)

                Spacer()
                Button { store.webView.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!store.canGoForward)

                Spacer()
                Button {
                    if store.isLoading { store.webView.stopLoading() }
                    else { store.webView.reload() }
                } label: {
                    Image(systemName: store.isLoading ? "xmark" : "arrow.clockwise")
                }

                Spacer()
                Button { store.load("https://duckduckgo.com/") } label: {
                    Image(systemName: "house")
                }

                Spacer()
                Button { store.load("https://ip.cx/") } label: {
                    Image(systemName: "checkmark.shield")
                }
            }
            .imageScale(.large)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .onAppear {
            if store.webView.url == nil { store.load(input) }
        }
        .onChange(of: store.displayURL) { newValue in
            if !newValue.isEmpty { input = newValue }
        }
    }
}

/// Owns the single WKWebView: incognito data store + spoof.js injection,
/// and publishes navigation state for the toolbar / address bar.
/// Everything the spoof does only applies INSIDE this app — iOS sandboxing
/// means Safari, the Claude app and every other app are unaffected.
final class WebViewStore: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var displayURL = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false

    override init() {
        let config = WKWebViewConfiguration()
        // Incognito: non-persistent data store — cookies, localStorage,
        // cache and history live in memory only and are wiped when the
        // app process ends. Trade-off: logins do NOT survive a restart.
        config.websiteDataStore = .nonPersistent()
        if let jsURL = Bundle.main.url(forResource: "spoof", withExtension: "js"),
           let js = try? String(contentsOf: jsURL, encoding: .utf8) {
            let script = WKUserScript(source: js,
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: false)
            config.userContentController.addUserScript(script)
        }
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 " +
            "Mobile/15E148 Safari/604.1"
    }

    /// Type a full URL, a bare domain (example.com), or search words.
    /// Search goes to DuckDuckGo. Change the template here to use Google.
    func load(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = Self.makeURL(from: text) else { return }
        webView.load(URLRequest(url: url))
    }

    static func makeURL(from text: String) -> URL? {
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return URL(string: text)
        }
        let looksLikeDomain = !text.contains(" ") && text.contains(".")
        if looksLikeDomain {
            return URL(string: "https://" + text)
        }
        let query = text.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: "https://duckduckgo.com/?q=" + query)
    }

    private func syncState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        if let current = webView.url?.absoluteString {
            displayURL = current
        }
    }

    func webView(_ webView: WKWebView,
                 didStartProvisionalNavigation navigation: WKNavigation!) {
        syncState()
    }
    func webView(_ webView: WKWebView,
                 didCommit navigation: WKNavigation!) {
        syncState()
    }
    func webView(_ webView: WKWebView,
                 didFinish navigation: WKNavigation!) {
        syncState()
    }
    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        syncState()
    }
    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        syncState()
    }
}

struct WebView: UIViewRepresentable {
    let store: WebViewStore

    func makeUIView(context: Context) -> WKWebView {
        store.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
