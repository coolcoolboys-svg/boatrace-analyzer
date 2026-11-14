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
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let controller = webView.window?.rootViewController else { completionHandler(); return }
            var presenter = controller
            while let presented = presenter.presentedViewController { presenter = presented }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            presenter.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard ProcessInfo.processInfo.arguments.contains("--ui-test-predict") else { return }
            let script = """
            (function() {
              let attempts = 0;
              const timer = setInterval(() => {
                const card = document.querySelector('#racecards details.racecard:not([data-inactive])');
                const button = card && card.querySelector('button[data-venue]');
                if (button) { card.open = true; button.click(); clearInterval(timer); }
                if (++attempts > 60) clearInterval(timer);
              }, 500);
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
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
        AnalyzerWebView()
            .preferredColorScheme(.light)
    }
}
