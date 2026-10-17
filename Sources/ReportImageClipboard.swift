import Cocoa
import UniformTypeIdentifiers

/// Native picture representations; pasted markup still goes through the report
/// fragment sanitizer and its per-picture SVG ID/style isolation.
@MainActor enum ReportImageClipboard {
    static let maximumBytes = 20_000_000 // Base64 fits the report's 30 MB paste bound.
    static let svgTypes = [UTType.svg.identifier, "image/svg+xml", "image/x-svg+xml", "SVG"].map { NSPasteboard.PasteboardType($0) }

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
        return nil
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

    static func write(image: NSImage, svg: Data?, to pasteboard: NSPasteboard) throws {
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
        item.setData(png, forType: .png)
        if let svg {
            let data = Data(try svgMarkup(svg).utf8)
            item.setData(data, forType: svgTypes[0])
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw LegacyReportError("The clipboard could not be written.") }
    }

    private static func checkSize(_ data: Data) throws {
        guard data.count <= maximumBytes else { throw LegacyReportError("The clipboard picture is too large. Copy a smaller picture.") }
    }
}
