import Cocoa

@main enum RChartExportRenderChecks {
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
        let fixture = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="120" viewBox="0 0 200 120">
          <style type="text/css"><![CDATA[
            .svglite line, .svglite polyline, .svglite polygon, .svglite path, .svglite rect, .svglite circle {
              fill:none; stroke:#000000; stroke-linecap:round; stroke-linejoin:round; stroke-miterlimit:10;
            }
          ]]></style>
          <defs><clipPath id="plotClip"><rect width="200" height="120"/></clipPath></defs>
          <g class="svglite" clip-path="url(#plotClip)">
          <rect width="200" height="120" style="fill:#ffffff;stroke:none"/>
          <rect x="10" y="10" width="40" height="30" style="fill:#0000ff;stroke:none"/>
          <circle cx="160" cy="90" r="15" style="fill:#ff0000;stroke:none"/>
          <polygon points="5,5 195,5 195,115 5,115"/>
          <path d="M5 115 L195 5" style="stroke:#008000;stroke-width:2;fill:none"/>
          </g>
        </svg>
        """.utf8)
        let data = try await RChartExport.pngData(fromSVG: fixture)
        guard let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide == 400, bitmap.pixelsHigh == 240,
              bitmap.bitsPerSample == 8 else { throw LegacyReportError("PNG must be an eight-bit image at twice the SVG's intrinsic size") }
        func check(_ x: Int, _ y: Int, _ rgb: (Int, Int, Int), _ message: String) throws {
            var pixel = [Int](repeating: 0, count: bitmap.samplesPerPixel)
            bitmap.getPixel(&pixel, atX: x, y: y)
            guard pixel.count == 4, abs(pixel[0] - rgb.0) <= 2, abs(pixel[1] - rgb.1) <= 2,
                  abs(pixel[2] - rgb.2) <= 2, pixel[3] >= 253 else {
                throw LegacyReportError("FAIL: \(message): raw RGBA \(pixel)")
            }
            print("PASS: \(message)")
        }
        try check(40, 40, (0, 0, 255), "top-left blue rectangle remains intact and correctly oriented")
        try check(320, 180, (255, 0, 0), "bottom-right red circle remains intact and correctly oriented")
        try check(200, 20, (255, 255, 255), "white background is not erased by the last SVG stroke")
        try check(2, 2, (255, 255, 255), "white corner remains opaque")
        // This generated R fixture retains svglite's stylesheet, nested clip
        // definitions and labels. AppKit rendered its plot region solid black.
        let styled = try RChartExport.svgData(from: URL(fileURLWithPath: "Tests/r-chart-export-styled.svg"))
        let styledPNG = try await RChartExport.pngData(fromSVG: styled)
        guard let styledBitmap = NSBitmapImageRep(data: styledPNG), styledBitmap.pixelsWide == 1008,
              styledBitmap.pixelsHigh == 1008 else { throw LegacyReportError("Styled R chart dimensions are incorrect") }
        func styledPixel(_ x: Int, _ y: Int) -> [Int] {
            var pixel = [Int](repeating: 0, count: styledBitmap.samplesPerPixel)
            styledBitmap.getPixel(&pixel, atX: x, y: y)
            return pixel
        }
        guard styledPixel(200, 200) == [255, 255, 255, 255] else {
            throw LegacyReportError("FAIL: styled R chart plot background was obscured by a black fill")
        }
        let red = styledPixel(533, 490)
        guard red.count == 4, red[0] > 245, red[1] < 10, red[2] < 10, red[3] == 255 else {
            throw LegacyReportError("FAIL: styled R chart final red line is missing or incorrectly positioned")
        }
        var labelPixels = 0
        for y in 40..<80 { for x in 350..<850 {
            let pixel = styledPixel(x, y)
            if pixel.count == 4 && pixel[0] < 100 && pixel[1] < 100 && pixel[2] < 100 && pixel[3] == 255 { labelPixels += 1 }
        } }
        guard labelPixels > 100 else { throw LegacyReportError("FAIL: styled R chart title was erased") }
        print("PASS: real styled R chart keeps white plot background, final red line and title")
        // Regenerate retained real-chart QA artifacts through the same helper.
        if CommandLine.arguments.count == 2 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try data.write(to: folder.appendingPathComponent("render-fixture.png"), options: .atomic)
            for name in ["earlier", "updated"] {
                let svg = try RChartExport.svgData(from: folder.appendingPathComponent(name + ".svg"))
                try await RChartExport.pngData(fromSVG: svg).write(to: folder.appendingPathComponent(name + ".png"), options: .atomic)
            }
        }
        print("All native chart rendering checks passed.")
    }
}
