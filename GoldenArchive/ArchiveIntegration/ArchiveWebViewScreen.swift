import SwiftUI
import WebKit

struct ArchiveWebViewScreen: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> ArchiveWebEngine { ArchiveWebEngine() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = context.coordinator.build()
        Task {
            await context.coordinator.restoreCookies()
            context.coordinator.load(url)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.loadIfChanged(url)
    }
}

final class ArchiveWebEngine: NSObject {
    weak var webView: WKWebView?

    private var currentURL: URL?
    private var lastURL: URL?
    private var redirectCount = 0
    private let maxRedirects = 70
    private var popups: [WKWebView] = []

    private let cookieKey = "wrapper_cookies"

    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    func build() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = WKProcessPool()
        configuration.websiteDataStore = .default()

        let preferences = WKPreferences()
        preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences = preferences

        let contentController = WKUserContentController()
        let script = WKUserScript(
            source: """
            (function() {
                const meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                document.head.appendChild(meta);
                const style = document.createElement('style');
                style.textContent = `body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}`;
                document.head.appendChild(style);
                document.addEventListener('gesturestart', e => e.preventDefault());
                document.addEventListener('gesturechange', e => e.preventDefault());
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        contentController.addUserScript(script)
        configuration.userContentController = contentController

        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = userAgent
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.bounces = false
        webView.scrollView.bouncesZoom = false
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView
        return webView
    }

    func load(_ url: URL) {
        currentURL = url
        redirectCount = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        webView?.load(request)
    }

    func loadIfChanged(_ url: URL) {
        guard url != currentURL else { return }
        load(url)
    }

    func restoreCookies() async {
        guard let stored = UserDefaults.standard.object(forKey: cookieKey)
                as? [String: [String: [String: Any]]] else { return }
        let cookieStore = webView?.configuration.websiteDataStore.httpCookieStore
        let cookies = stored.values.flatMap { $0.values }.compactMap { dict -> HTTPCookie? in
            let props = Dictionary(uniqueKeysWithValues: dict.map { (HTTPCookiePropertyKey($0.key), $0.value) })
            return HTTPCookie(properties: props)
        }
        cookies.forEach { cookieStore?.setCookie($0) }
    }

    private func saveCookies(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            var store: [String: [String: [String: Any]]] = [:]
            for cookie in cookies {
                guard let props = cookie.properties else { continue }
                var domain = store[cookie.domain] ?? [:]
                domain[cookie.name] = Dictionary(uniqueKeysWithValues: props.map { ($0.key.rawValue, $0.value) })
                store[cookie.domain] = domain
            }
            UserDefaults.standard.set(store, forKey: self.cookieKey)
        }
    }
}

extension ArchiveWebEngine: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
        lastURL = url
        let scheme = (url.scheme ?? "").lowercased()
        let path = url.absoluteString.lowercased()
        let allowedSchemes: Set<String> = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let specialPaths = ["srcdoc", "about:blank", "about:srcdoc"]
        if allowedSchemes.contains(scheme) || specialPaths.contains(where: { path.hasPrefix($0) }) {
            decisionHandler(.allow)
        } else {
            UIApplication.shared.open(url, options: [:])
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        redirectCount += 1
        if redirectCount > maxRedirects {
            webView.stopLoading()
            if let recovery = lastURL { webView.load(URLRequest(url: recovery)) }
            redirectCount = 0
            return
        }
        lastURL = webView.url
        saveCookies(from: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURL = webView.url ?? currentURL
        redirectCount = 0
        saveCookies(from: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorHTTPTooManyRedirects, let recovery = lastURL {
            webView.load(URLRequest(url: recovery))
        }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}

extension ArchiveWebEngine: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        if let url = navigationAction.request.url {
            let scheme = (url.scheme ?? "").lowercased()
            let webSchemes: Set<String> = ["http", "https", "about", "blob", "data", "javascript", "file"]
            if !webSchemes.contains(scheme) {
                UIApplication.shared.open(url, options: [:])
                return nil
            }
        }
        let popup = WKWebView(frame: webView.bounds, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.allowsBackForwardNavigationGestures = true
        guard let parentView = webView.superview else { return nil }
        parentView.addSubview(popup)
        popup.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            popup.topAnchor.constraint(equalTo: webView.topAnchor),
            popup.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            popup.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
        ])
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePopupPan(_:)))
        gesture.delegate = self
        popup.scrollView.panGestureRecognizer.require(toFail: gesture)
        popup.addGestureRecognizer(gesture)
        popups.append(popup)
        if let url = navigationAction.request.url, url.absoluteString != "about:blank" {
            popup.load(navigationAction.request)
        }
        return popup
    }

    @objc private func handlePopupPan(_ recognizer: UIPanGestureRecognizer) {
        guard let popupView = recognizer.view else { return }
        let translation = recognizer.translation(in: popupView)
        let velocity = recognizer.velocity(in: popupView)
        switch recognizer.state {
        case .changed:
            if translation.x > 0 { popupView.transform = CGAffineTransform(translationX: translation.x, y: 0) }
        case .ended, .cancelled:
            let shouldClose = translation.x > popupView.bounds.width * 0.4 || velocity.x > 800
            if shouldClose {
                UIView.animate(withDuration: 0.25, animations: {
                    popupView.transform = CGAffineTransform(translationX: popupView.bounds.width, y: 0)
                }) { [weak self] _ in self?.dismissTopPopup() }
            } else {
                UIView.animate(withDuration: 0.2) { popupView.transform = .identity }
            }
        default:
            break
        }
    }

    private func dismissTopPopup() {
        guard let last = popups.last else { return }
        last.removeFromSuperview()
        popups.removeLast()
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let index = popups.firstIndex(of: webView) {
            webView.removeFromSuperview()
            popups.remove(at: index)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

extension ArchiveWebEngine: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
        let velocity = pan.velocity(in: view)
        let translation = pan.translation(in: view)
        return translation.x > 0 && abs(velocity.x) > abs(velocity.y)
    }
}
