import SwiftUI
import WebKit

struct SVGPreview: View {
    let svg: String
    let aspectRatio: Double

    var body: some View {
        SVGWebView(svg: svg)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .accessibilityLabel("Rendered flight map preview")
            .accessibilityIdentifier("route.preview")
    }
}

private func previewHTML(for svg: String) -> String {
    """
    <!doctype html>
    <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; }
          body { display: flex; align-items: center; justify-content: center; }
          svg { width: 100%; height: 100%; display: block; }
        </style>
      </head>
      <body>\(svg)</body>
    </html>
    """
}

#if os(macOS)
private struct SVGWebView: NSViewRepresentable {
    let svg: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.svg != svg else { return }
        context.coordinator.svg = svg
        webView.loadHTMLString(previewHTML(for: svg), baseURL: nil)
    }

    final class Coordinator {
        var svg = ""
    }
}
#else
private struct SVGWebView: UIViewRepresentable {
    let svg: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.svg != svg else { return }
        context.coordinator.svg = svg
        webView.loadHTMLString(previewHTML(for: svg), baseURL: nil)
    }

    final class Coordinator {
        var svg = ""
    }
}
#endif
