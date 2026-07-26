import SwiftUI
import WebKit

// MARK: - The view

/// Wraps `WKWebView` for SwiftUI and loads the bundled course.
struct CourseView: UIViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // The course is a JavaScript slide deck.
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Persistent (not ephemeral) so localStorage survives quitting the app.
        // This is what remembers the current slide and the earned badges.
        config.websiteDataStore = .default()

        // Nothing in the course plays media, but leaving this at the default
        // would let a future embed autoplay over a reader unprompted.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all

        // See CourseSchemeHandler — this is the reason the app does not simply
        // call loadFileURL.
        config.setURLSchemeHandler(context.coordinator.schemeHandler,
                                   forURLScheme: CourseSchemeHandler.scheme)

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator

        // Match --paper exactly so there is no white frame during load or when
        // the deck is rubber-banded past its edge.
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0x0f / 255, green: 0x15 / 255, blue: 0x13 / 255, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.contentInsetAdjustmentBehavior = .never

        // Edge-swipe goes back a slide: the mobile layer pushes one history
        // entry per slide, so the platform's own back gesture lands on the
        // previous lesson, which is what an iOS reader expects it to do.
        web.allowsBackForwardNavigationGestures = true

        // Long-press link preview has nothing to preview in an offline deck.
        web.allowsLinkPreview = false

        web.load(URLRequest(url: CourseSchemeHandler.courseURL))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Nothing to sync — the deck owns all of its own state.
    }

    // MARK: - Delegates

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let schemeHandler = CourseSchemeHandler()

        /// Keep the reader inside the course; send the open web to Safari.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel); return
            }
            if url.scheme == CourseSchemeHandler.scheme {
                decisionHandler(.allow); return
            }
            if navigationAction.navigationType == .linkActivated,
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        /// target="_blank" has no window to open into here — reuse this one.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, url.scheme != CourseSchemeHandler.scheme {
                UIApplication.shared.open(url)
            }
            return nil
        }
    }
}

// MARK: - Serving the course

/// Serves the bundled course over a private `academy://` scheme.
///
/// The obvious alternative — `loadFileURL(_:allowingReadAccessTo:)` — is what
/// most WebView wrappers reach for and it is the reason so many of them lose
/// the reader's progress. A `file://` document is treated as an opaque origin
/// by WebKit, and an opaque origin gets no persistent `localStorage`; writes
/// either throw a SecurityError or evaporate when the app is relaunched.
///
/// A custom scheme gives the document a real, stable origin, so `localStorage`
/// behaves exactly as it does in a browser. This is the same trick Capacitor
/// and Ionic use, and for the same reason.
final class CourseSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "academy"
    static let courseURL = URL(string: "\(scheme)://course/course.html")!

    /// Only these are ever served. The deck is one file, but keeping this a
    /// list rather than a wildcard means a path the bundle does not contain
    /// fails as a 404 rather than as a directory traversal.
    private static let served: [String: String] = [
        "/course.html": "text/html; charset=utf-8"
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let path = urlSchemeTask.request.url?.path ?? ""

        guard let mime = Self.served[path],
              let name = path.split(separator: "/").last.map(String.init),
              let fileURL = Bundle.main.url(forResource: (name as NSString).deletingPathExtension,
                                            withExtension: (name as NSString).pathExtension),
              let data = try? Data(contentsOf: fileURL)
        else {
            urlSchemeTask.didFailWithError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist,
                        userInfo: [NSLocalizedDescriptionKey: "Not bundled: \(path)"]))
            return
        }

        let response = HTTPURLResponse(
            url: urlSchemeTask.request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length": String(data.count),
                // The course loads nothing external. Saying so in a header as
                // well as in fact means a future edit that adds a CDN link
                // fails visibly here instead of quietly working online only.
                "Content-Security-Policy":
                    "default-src 'self' 'unsafe-inline' data:; script-src 'unsafe-inline'; connect-src 'none'"
            ])!

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Serving is synchronous and file-backed; there is nothing to cancel.
    }
}
