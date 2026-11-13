import SwiftUI
import WebKit

struct AnalyzerWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0.945, green: 0.976, blue: 0.988, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.allowsBackForwardNavigationGestures = true
        guard let url = Bundle.main.url(forResource: "Analyzer", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            view.loadHTMLString("<p>画面を読み込めませんでした。</p>", baseURL: nil)
            return view
        }
        view.loadHTMLString(html, baseURL: URL(string: "https://coolcoolboys-svg.github.io/boatrace-analyzer/"))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, action.targetFrame == nil {
                UIApplication.shared.open(url)
            }
            return nil
        }
    }
}

struct AnalyzerAppRoot: View {
    var body: some View {
        AnalyzerWebView().ignoresSafeArea(.container, edges: .bottom)
            .preferredColorScheme(.light)
    }
}
