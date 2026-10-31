import Cocoa
import UniformTypeIdentifiers

/// Native picture representations; pasted markup still goes through the report
/// fragment sanitizer and its per-picture SVG ID/style isolation.
@MainActor enum ReportImageClipboard {
    static let maximumBytes = 20_000_000 // Base64 fits the report's 30 MB paste bound.
    static let reportFragmentType = NSPasteboard.PasteboardType("com.statsdirect.report-fragment.html")
    static let officeSVGType = NSPasteboard.PasteboardType("com.microsoft.image-svg-xml")
    static let svgTypes = [UTType.svg.identifier, "image/svg+xml", "image/x-svg+xml", "SVG", officeSVGType.rawValue].map { NSPasteboard.PasteboardType($0) }

    static func svgMarkup(_ data: Data) throws -> String {
        try checkSize(data)
        // XMLDocument detects UTF-8/UTF-16 BOMs. Ignore external DTDs even for
        // older R SVGs that include a public SVG document type declaration.
        let document = try XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever)
        guard let root = document.rootElement(), root.localName == "svg",
              root.uri == nil || root.uri == "" || root.uri == "http://www.w3.org/2000/svg" else {
            throw LegacyReportError("The clipboard picture has no SVG element.")
        }
        let markup = root.xmlString(options: .nodeCompactEmptyElement)
        try checkSize(Data(markup.utf8))
        return markup
    }

    static func svgHTML(from pasteboard: NSPasteboard) throws -> String? {
        for type in svgTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty { return try svgMarkup(data) }
        }
        // Keep accepting native SVG file copies too; the
        // report importer still sanitizes and isolates the returned markup.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           urls.count == 1, let url = urls.first, url.pathExtension.lowercased() == "svg" {
            return try svgMarkup(svgFileData(url))
        }
        return nil
    }

    /// Legacy file-transfer fallback. Ordinary chart copying uses the Office
    /// SVG type together with native SVG and PNG representations below.
    static func writeSVGFile(_ url: URL, to pasteboard: NSPasteboard) throws {
        _ = try svgMarkup(svgFileData(url)) // Validate before replacing the clipboard.
        pasteboard.clearContents()
        guard pasteboard.writeObjects([url as NSURL]) else {
            throw LegacyReportError("The SVG chart could not be copied.")
        }
    }

    /// One clipboard item offers vector SVG to Office and native image readers,
    /// plus a standard PNG fallback. No R graphics device or package is involved.
    static func writeSVG(_ data: Data, reportFragment: String? = nil, to pasteboard: NSPasteboard) throws {
        try checkReportFragment(reportFragment)
        _ = try svgMarkup(data)
        guard let image = NSImage(data: data), image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else {
            throw LegacyReportError("The SVG chart could not be rendered for the clipboard.")
        }
        let scale = 1600 / max(image.size.width, image.size.height)
        image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        try write(image: image, svg: data, to: pasteboard, reportFragment: reportFragment)
    }

    private static func checkReportFragment(_ fragment: String?) throws {
        guard (fragment?.utf8.count ?? 0) <= 30_000_000 else {
            throw LegacyReportError("The report selection is too large to copy.")
        }
    }

    private static func svgFileData(_ url: URL) throws -> Data {
        guard url.isFileURL, url.pathExtension.lowercased() == "svg" else {
            throw LegacyReportError("The chart is not a local SVG file.")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw LegacyReportError("The SVG chart is unavailable or too large to copy.")
        }
        let data = try Data(contentsOf: url)
        try checkSize(data)
        return data
    }

    static func rasterHTML(from pasteboard: NSPasteboard) throws -> String? {
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else { return nil }
        try checkSize(data)
        guard let image = NSBitmapImageRep(data: data), let png = image.representation(using: .png, properties: [:]) else {
            throw LegacyReportError("The clipboard picture could not be read.")
        }
        try checkSize(png)
        return "<img alt=\"Pasted image\" src=\"data:image/png;base64,\(png.base64EncodedString())\">"
    }

    static func write(image: NSImage, svg: Data?, to pasteboard: NSPasteboard, reportFragment: String? = nil) throws {
        try checkReportFragment(reportFragment)
        if let svg { _ = try svgMarkup(svg) }
        let vector = svg
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw LegacyReportError("The chart could not be copied as a picture.")
        }
        // SVG previews can use a floating-point/wide-gamut backing image that
        // ImageIO cannot write directly as PNG. Render a standard 8-bit fallback.
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let raster = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: raster).representation(using: .png, properties: [:]) else {
            throw LegacyReportError("The chart could not be copied as a picture.")
        }
        try checkSize(png)
        let item = NSPasteboardItem()
        if let vector {
            // Office for Mac recognizes its own SVG UTI. The public SVG type
            // alone was ignored in favour of PNG by both Word and PowerPoint.
            guard item.setData(vector, forType: officeSVGType),
                  item.setData(vector, forType: svgTypes[0]) else {
                throw LegacyReportError("The SVG chart could not be prepared for the clipboard.")
            }
        }
        guard item.setData(png, forType: .png) else { throw LegacyReportError("The chart PNG could not be prepared for the clipboard.") }
        if let reportFragment {
            guard item.setString(reportFragment, forType: reportFragmentType) else {
                throw LegacyReportError("The report chart's formatting could not be copied.")
            }
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw LegacyReportError("The clipboard could not be written.") }
    }

    private static func checkSize(_ data: Data) throws {
        guard data.count <= maximumBytes else { throw LegacyReportError("The clipboard picture is too large. Copy a smaller picture.") }
    }
}
