import Cocoa
import WebKit

/// Native exports of an already completed R chart. No R device is opened.
@MainActor enum RChartExport {
    static let maximumBytes = 64 * 1024 * 1024
    static let maximumPixels = 64_000_000

    /// Return the retained SVG bytes, including its original glyphs and styles.
    static func svgData(from url: URL) throws -> Data {
        guard url.isFileURL, url.pathExtension.lowercased() == "svg" else {
            throw LegacyReportError("The chart is not a local SVG file.")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw LegacyReportError("The chart SVG is unavailable or too large to export.")
        }
        let data = try Data(contentsOf: url)
        try validateSVG(data)
        return data
    }

    static func pngData(fromSVG data: Data, scale: CGFloat = 2) async throws -> Data {
        try validateSVG(data)
        // Cocoa supplies point dimensions only. Its SVG renderer does not
        // support the embedded stylesheets used by R charts, so WebKit draws.
        guard let image = NSImage(data: data) else {
            throw LegacyReportError("The chart SVG dimensions could not be read.")
        }
        let size = try pixelSize(image.size, scale: scale)
        try Task.checkCancellation()
        let renderer = RChartPNGRenderer()
        defer { renderer.web.stopLoading(); renderer.web.navigationDelegate = nil }
        try await renderer.load()
        let value = try await renderer.web.callAsyncJavaScript("""
        const image = new Image();
        image.src = 'data:image/svg+xml;base64,' + svg;
        await image.decode();
        const canvas = document.createElement('canvas');
        canvas.width = width; canvas.height = height;
        const context = canvas.getContext('2d', {willReadFrequently:true});
        if (!context) throw new Error('The chart canvas could not be created.');
        context.drawImage(image, 0, 0, width, height);
        return canvas.toDataURL('image/png');
        """, arguments: ["svg": data.base64EncodedString(), "width": size.width, "height": size.height],
            in: nil, contentWorld: .page)
        try Task.checkCancellation()
        let prefix = "data:image/png;base64,"
        guard let value = value as? String, value.hasPrefix(prefix), value.utf8.count <= maximumBytes * 4 / 3 + prefix.count + 4,
              let png = Data(base64Encoded: String(value.dropFirst(prefix.count))), !png.isEmpty, png.count <= maximumBytes else {
            throw LegacyReportError("The chart PNG could not be generated or is too large to export.")
        }
        return png
    }

    private static func pixelSize(_ size: NSSize, scale: CGFloat) throws -> (width: Int, height: Int) {
        let width = ceil(size.width * scale), height = ceil(size.height * scale)
        guard scale.isFinite, scale > 0, width.isFinite, height.isFinite,
              width >= 1, height >= 1, width * height <= CGFloat(maximumPixels) else {
            throw LegacyReportError("The chart is too large or could not be rendered as PNG.")
        }
        return (Int(width), Int(height))
    }

    /// Explicit dimensions keep vector rendering at the requested resolution;
    /// an 8-bit sRGB context also handles wide-gamut or float-backed previews.
    static func pngData(fromImage image: NSImage, scale: CGFloat = 1) throws -> Data {
        let size = try pixelSize(image.size, scale: scale)
        let width = size.width, height = size.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw LegacyReportError("The chart is too large or could not be rendered as PNG.")
        }
        guard let scaled = image.copy() as? NSImage else {
            throw LegacyReportError("The chart could not be rendered as PNG.")
        }
        scaled.size = NSSize(width: CGFloat(width), height: CGFloat(height))
        guard let source = scaled.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw LegacyReportError("The chart could not be rendered as PNG.")
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let raster = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: raster).representation(using: .png, properties: [:]),
              data.count <= maximumBytes else {
            throw LegacyReportError("The chart PNG could not be generated or is too large to export.")
        }
        return data
    }

    private static func validateSVG(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw LegacyReportError("The chart SVG is unavailable or too large to export.")
        }
        let document = try XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever)
        guard let root = document.rootElement(), root.localName == "svg",
              root.uri == nil || root.uri == "" || root.uri == "http://www.w3.org/2000/svg" else {
            throw LegacyReportError("The chart file does not contain a readable SVG image.")
        }
    }
}

/// An SVG is decoded only as an inert image, never inserted into page DOM.
/// The controlled page has no network or file access and keeps no web data.
@MainActor private final class RChartPNGRenderer: NSObject, WKNavigationDelegate {
    let web: WKWebView
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        super.init()
        web.navigationDelegate = self
    }

    func load() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 10_000_000_000) }
                catch { return }
                self?.finish(.failure(LegacyReportError("The chart renderer did not become ready.")))
            }
            web.loadHTMLString("""
            <!doctype html><html><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; base-uri 'none'; form-action 'none'">
            </head><body></body></html>
            """, baseURL: nil)
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        timeout?.cancel(); timeout = nil
        let waiting = continuation; continuation = nil
        waiting?.resume(with: result)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(LegacyReportError("The chart renderer stopped unexpectedly.")))
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel)
    }
}
