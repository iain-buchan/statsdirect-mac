import Cocoa

@main enum OfficeSVGChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do { try await run(); exit(0) }
            catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        }
        NSApp.run()
    }
    @MainActor static func run() async throws {
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw LegacyReportError("FAIL: " + message) }
            print("PASS: " + message)
        }
        func svg(_ text: String, root: String = "") -> Data {
            Data("<svg xmlns='http://www.w3.org/2000/svg' width='600' height='450' viewBox='0 0 600 450' \(root)>\(text)</svg>".utf8)
        }
        let source = svg("""
        <rect width='600' height='450' fill='white'/>
        <g font-family='Arial' font-size='20'>
          <text id='plain' x='80' y='80' fill='#000000'>Risk ratio 2.50 ± 0.13</text>
          <text id='bold' x='80' y='140' font-weight='bold'>Bold 95% confidence interval</text>
          <text id='italic' x='80' y='200' font-style='italic'>Greek μ and minus −1.25</text>
          <text id='holes' x='80' y='280' font-size='48'>B8O</text>
          <text id='rotation' x='0' y='0' transform='translate(40 420) rotate(-90)' font-weight='bold'>Rotated difference</text>
          <text id='paint' x='80' y='340' fill='#123456' opacity='0.75' clip-path='url(#clip)' aria-label='Existing accessible label'>&lt;5 &amp; ≥2</text>
        </g>
        <defs><clipPath id='clip'><rect width='600' height='450'/></clipPath></defs>
        """)
        let result = OfficeSVG.forClipboard(source)
        let document = try XMLDocument(data: result)
        let text = try document.nodes(forXPath: "//*[local-name()='text']"), paths = try document.nodes(forXPath: "//*[local-name()='path']").compactMap { $0 as? XMLElement }
        try check(result != source && text.isEmpty && paths.count == 6, "canonical inherited-font labels become six vector paths")
        let rotated = paths.first { $0.attribute(forName: "id")?.stringValue == "rotation" }
        try check(rotated?.attribute(forName: "transform")?.stringValue == "translate(40 420) rotate(-90)", "rotated caption keeps its original SVG transform")
        let paint = paths.first { $0.attribute(forName: "id")?.stringValue == "paint" }
        try check(paint?.attribute(forName: "fill")?.stringValue == "#123456" && paint?.attribute(forName: "opacity")?.stringValue == "0.75"
                  && paint?.attribute(forName: "clip-path")?.stringValue == "url(#clip)" && paint?.attribute(forName: "aria-label")?.stringValue == "Existing accessible label"
                  && paint?.children?.first?.stringValue == "<5 & ≥2", "paint, clipping, identity and accessible label survive outlining")
        try check(paths.allSatisfy { $0.attribute(forName: "d")?.stringValue?.contains("Z") == true && $0.attribute(forName: "fill-rule")?.stringValue == "nonzero" }, "glyph contours close with nonzero winding for letter counters")
        let canonical = "<text x='10' y='30' font-family='Arial' font-size='20'>Label</text>"
        let unsupported = [
            canonical.replacingOccurrences(of: ">Label<", with: "><tspan>Label</tspan><"),
            canonical.replacingOccurrences(of: "font-family='Arial'", with: "font-family='No such font StatsDirect'"),
            canonical.replacingOccurrences(of: "font-family='Arial'", with: ""),
            canonical.replacingOccurrences(of: "x='10'", with: "x='10 20'"),
            canonical.replacingOccurrences(of: "font-size='20'", with: "font-size='2em'"),
            canonical.replacingOccurrences(of: "Label", with: String(repeating: "X", count: 4097)),
            canonical.replacingOccurrences(of: "Label", with: "Color 😀 emoji"),
            "<style>text { fill: red; }</style>" + canonical,
            "<g style='font-family:Times New Roman'>" + canonical + "</g>",
            "<g style='font-size:42px;font-weight:bold'>" + canonical + "</g>",
            canonical.replacingOccurrences(of: "Label", with: "RTL אבג label"),
            "<g direction='rtl'>" + canonical + "</g>",
            "<g unicode-bidi='embed'>" + canonical + "</g>"
        ] + ["dx='1'", "dy='1'", "rotate='45'", "textLength='80'", "lengthAdjust='spacing'", "text-anchor='middle'", "writing-mode='vertical-rl'",
             "dominant-baseline='middle'", "letter-spacing='1'", "word-spacing='1'", "style='font-weight:bold'", "font-weight='bolder'", "font-style='oblique'", "direction='rtl'", "unicode-bidi='bidi-override'", "font-kerning='none'", "kerning='0'",
             "font-feature-settings='&quot;kern&quot; 0'", "font-variant-ligatures='none'", "white-space='pre'"].map {
            canonical.replacingOccurrences(of: " x=", with: " \($0) x=")
        }
        let nonstandardWeights = ["100", "200", "300", "500", "600", "800", "900"].map {
            canonical.replacingOccurrences(of: " x=", with: " font-weight='\($0)' x=")
        }
        for (index, fragment) in (unsupported + nonstandardWeights).enumerated() {
            let data = svg(fragment)
            try check(OfficeSVG.forClipboard(data) == data, "unsupported label case \(index + 1) remains byte-identical")
        }
        for weight in ["normal", "400", "bold", "700"] {
            let data = svg(canonical.replacingOccurrences(of: " x=", with: " font-weight='\(weight)' x="))
            try check(OfficeSVG.forClipboard(data) != data, "explicit normal/bold weight \(weight) retains its supported face")
        }
        let viewport = svg(canonical, root: "style='width:100%;max-width:100%;height:auto;'")
        try check(OfficeSVG.forClipboard(viewport) != viewport, "root viewport-only sizing is resolved without altering font inheritance")
        let rootFont = svg(canonical, root: "style='width:100%;font-size:42px;'")
        try check(OfficeSVG.forClipboard(rootFont) == rootFont, "root viewport sizing cannot hide an unresolved font declaration")
        let failedLabel = canonical.replacingOccurrences(of: "Label", with: String(repeating: "W", count: 1000) + "😀")
        let failedRepeated = svg(String(repeating: failedLabel, count: 60) + canonical)
        try check(OfficeSVG.forClipboard(failedRepeated) == failedRepeated, "repeated labels failing at emoji consume their attempted contour budget before a later label")
        let rejected = "<text font-family='Unknown font StatsDirect' font-size='20'>Unknown</text>"
        let attempts = svg(String(repeating: rejected, count: 10_000) + canonical)
        try check(OfficeSVG.forClipboard(attempts) == attempts, "early unsupported labels consume the attempt budget before later labels")
        let complex = svg(canonical.replacingOccurrences(of: "Label", with: String(repeating: "@", count: 4096)))
        try check(OfficeSVG.forClipboard(complex) == complex, "a complex full-length label respects the native contour budget and remains unchanged")
        let fallback = svg(canonical.replacingOccurrences(of: "font-family='Arial'", with: "font-family='No such font StatsDirect,Arial'"))
        try check(OfficeSVG.forClipboard(fallback) != fallback, "an explicit available fallback family is used without substituting an unknown-only family")
        let r = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/RCharts/svglite-1.svg"))
        try check(OfficeSVG.forClipboard(r) == r, "R stylesheet SVG stays byte-identical")
        let glyph = svg("<path d='M0 0L10 10Z'/>")
        try check(OfficeSVG.forClipboard(glyph) == glyph, "existing glyph-path SVG stays byte-identical")
        let dtd = Data("<!DOCTYPE svg [<!ENTITY x 'Label'>]>".utf8) + svg(canonical)
        try check(OfficeSVG.forClipboard(dtd) == dtd && OfficeSVG.forClipboard(Data("<svg><text>".utf8)) == Data("<svg><text>".utf8), "DTD and malformed XML fail open without parsing external resources")
        let large = Data(repeating: 32, count: 20_000_001)
        try check(OfficeSVG.forClipboard(large) == large, "oversized input stays unchanged")
        let originalPNG = try await RChartExport.pngData(fromSVG: source), outlinedPNG = try await RChartExport.pngData(fromSVG: result)
        guard let original = NSBitmapImageRep(data: originalPNG), let outlined = NSBitmapImageRep(data: outlinedPNG) else { throw LegacyReportError("Could not read PNG verification images") }
        try check(original.pixelsWide == outlined.pixelsWide && original.pixelsHigh == outlined.pixelsHigh, "outlined chart retains its raster dimensions")
        func metrics(_ bitmap: NSBitmapImageRep, rect: (Int, Int, Int, Int)) -> (Int, Int, Int, Int, Int) {
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, count = 0
            for y in rect.1..<rect.3 { for x in rect.0..<rect.2 {
                var pixel = [Int](repeating: 0, count: bitmap.samplesPerPixel)
                bitmap.getPixel(&pixel, atX: x, y: y)
                if pixel.count == 4 && pixel[3] > 128 && pixel[0] < 128 && pixel[1] < 128 && pixel[2] < 128 {
                    minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y); count += 1
                }
            } }
            return (minX, minY, maxX, maxY, count)
        }
        for (name, rect) in [("plain numeric", (140, 100, 1100, 175)), ("bold", (140, 220, 1100, 300)),
                             ("italic Greek", (140, 340, 1100, 420)), ("letter counters", (140, 450, 450, 580)),
                             ("rotated caption", (25, 350, 100, 850))] {
            let before = metrics(original, rect: rect), after = metrics(outlined, rect: rect)
            try check(before.4 > 0 && after.4 > 0 && abs(before.0 - after.0) <= 2 && abs(before.1 - after.1) <= 2
                      && abs(before.2 - after.2) <= 2 && abs(before.3 - after.3) <= 2
                      && abs(Double(after.4) / Double(before.4) - 1) < 0.15, "\(name) glyph bounds, baseline and filled area match the text rendering")
        }
        if let input = ProcessInfo.processInfo.environment["STATSDIRECT_OFFICE_SVG_PEFR"] {
            let original = try Data(contentsOf: URL(fileURLWithPath: input)), publicSVG = OfficeSVG.forClipboard(original)
            let parsed = try XMLDocument(data: publicSVG)
            let remaining = try parsed.nodes(forXPath: "//*[local-name()='text' or local-name()='tspan']")
            let points = try parsed.nodes(forXPath: "//*[local-name()='ellipse']"), lines = try parsed.nodes(forXPath: "//*[local-name()='line']")
            try check(publicSVG != original && remaining.isEmpty && points.count == 9 && lines.count == 19, "actual report PEFR public SVG outlines all17labels and preserves ninepoints/nineteenlines")
            func onWhitePage(_ svg: Data) throws -> Data {
                let page = try XMLDocument(data: svg)
                let background = XMLElement(name: "rect", uri: "http://www.w3.org/2000/svg")
                for (name, value) in [("width", "100%"), ("height", "100%"), ("fill", "white")] {
                    background.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
                }
                page.rootElement()?.insertChild(background, at: 0)
                return page.xmlData
            }
            let beforePNG = try await RChartExport.pngData(fromSVG: onWhitePage(original)), afterPNG = try await RChartExport.pngData(fromSVG: onWhitePage(publicSVG))
            guard let beforeImage = NSBitmapImageRep(data: beforePNG), let afterImage = NSBitmapImageRep(data: afterPNG) else { throw LegacyReportError("PEFR verification images are unreadable") }
            let scale = Double(beforeImage.pixelsWide) / 1132
            for (name, roi) in [("PEFR rotated Y caption", (45, 150, 78, 620)), ("PEFR X caption", (200, 720, 980, 770))] {
                let rect = (Int(Double(roi.0) * scale), Int(Double(roi.1) * scale), Int(Double(roi.2) * scale), Int(Double(roi.3) * scale))
                let before = metrics(beforeImage, rect: rect), after = metrics(afterImage, rect: rect)
                try check(before.4 > 0 && after.4 > 0 && abs(before.0 - after.0) <= 2 && abs(before.1 - after.1) <= 2
                          && abs(before.2 - after.2) <= 2 && abs(before.3 - after.3) <= 2 && abs(Double(after.4) / Double(before.4) - 1) < 0.15,
                          "\(name) pixelbounds/baseline match canonical public text")
            }
            if let folder = ProcessInfo.processInfo.environment["STATSDIRECT_OFFICE_SVG_QA"] {
                let url = URL(fileURLWithPath: folder, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                for (name, data) in [("pefr-original.svg", original), ("pefr-outlined.svg", publicSVG), ("pefr-original.png", beforePNG), ("pefr-outlined.png", afterPNG)] {
                    try data.write(to: url.appendingPathComponent(name), options: .atomic)
                }
            }
        }
        if let folder = ProcessInfo.processInfo.environment["STATSDIRECT_OFFICE_SVG_QA"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for (name, data) in [("original.svg", source), ("outlined.svg", result), ("original.png", originalPNG), ("outlined.png", outlinedPNG)] {
                try data.write(to: url.appendingPathComponent(name), options: .atomic)
            }
        }
        print("All Office SVG checks passed.")
    }
}
