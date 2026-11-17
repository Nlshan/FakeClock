import SwiftUI
import WebKit

/// Instagram tab (§8): a real `WKWebView` pointed at the mobile site.
///
/// This is a genuine web view, not a redirect: it keeps cookies, sessions and
/// the logged-in state inside the app, supports inline video and touch
/// scrolling, and never hands the user off to Safari. It is shown only after
/// the app's own authentication gate has passed, so Instagram is protected by
/// the same lock as every other tab.
///
/// Safe area: the web view fills the tab, so Instagram's own top bar lands
/// below the tab bar and the status bar rather than under the Dynamic Island.
/// No full-screen overrides are applied here — WebKit handles the keyboard
/// natively, so only the container is the app's to manage.
struct InstagramView: View {
    @StateObject private var viewModel = InstagramViewModel()

    var body: some View {
        NavigationStack {
            viewModel.view
                .overlay(alignment: .topTrailing) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(Theme.Palette.accent)
                            .padding(.top, Theme.Metrics.spacingM)
                            .padding(.trailing, Theme.Metrics.spacingM)
                    }
                }
                .navigationTitle("Instagram")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!viewModel.canGoBack)
                        .accessibilityLabel("Go back")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.refresh()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .accessibilityLabel("Refresh")
                    }
                }
                .accessibilityIdentifier(A11y.instagramScreen)
        }
    }
}

/// Wraps a `WKWebView` as a SwiftUI `View` so the tab can own it.
///
/// The view model is the only place that touches WebKit, which keeps the view
/// layer thin and the configuration (user agent, viewport, inline video) easy
/// to inspect.
@MainActor
final class InstagramViewModel: ObservableObject, WKNavigationDelegate {
    static let destinationURL = URL(string: "https://www.instagram.com")!

    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false

    private let web: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = [.audio, .video]
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.scrollsToTop = true
        view.isOpaque = false
        view.backgroundColor = Theme.Palette.background
        self.web = view
        load()
    }

    /// The web view, exposed as a SwiftUI `View`.
    var view: some View {
        WebViewWrapper(web: web)
    }

    func load() {
        web.load(URLRequest(url: Self.destinationURL))
    }

    func refresh() {
        web.reload()
    }

    func goBack() {
        web.goBack()
    }

    // MARK: - WKNavigationDelegate

    func WebView(_ WebView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func WebView(_ WebView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        canGoBack = WebView.canGoBack
    }

    func WebView(_ WebView: WKWebView, didCommit navigation: WKNavigation!) {
        canGoBack = WebView.canGoBack
    }

    func WebView(_ WebView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }
}

/// Bridges `WKWebView` (a `UIView`/`NSView`) into the SwiftUI view hierarchy.
///
/// `SwiftUI.View` cannot host a `WKWebView` directly, so this struct is the
/// bridge. It is kept separate from the view model so the model stays a plain
/// observable object and the wrapper can be reused by any future web view.
struct WebViewWrapper: UIViewRepresentable {
    let web: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}