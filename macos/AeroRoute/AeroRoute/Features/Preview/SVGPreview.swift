import SwiftUI
#if os(macOS)
import AppKit
#else
import WebKit
#endif

struct SVGPreview: View {
    let svg: String
    let aspectRatio: Double

    var body: some View {
        Group {
#if os(macOS)
            NativeSVGImage(svg: svg)
#else
            SVGWebView(svg: svg)
                .aspectRatio(aspectRatio, contentMode: .fit)
#endif
        }
        .accessibilityLabel("Rendered flight map preview")
        .accessibilityIdentifier("route.preview")
    }
}

#if os(macOS)
func macOSSVGPreviewImage(from svg: String) -> NSImage? {
    NSImage(data: Data(svg.utf8))
}

private struct NativeSVGImage: View {
    let svg: String

    var body: some View {
        FlexibleSVGImageView(image: macOSSVGPreviewImage(from: svg))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FlexibleSVGImageView: NSViewRepresentable {
    let image: NSImage?

    func makeNSView(context: Context) -> NSImageView {
        let imageView = FlexibleNSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        imageView.image = image
    }
}

private final class FlexibleNSImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        .zero
    }
}
#else
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
