import Cocoa
import WebKit
import PDFKit

extension ReportExportTests {
    @MainActor static func importedRCharts(_ v: Viewer, output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/Fixtures/RCharts")
        var charts = try (1...2).map { try String(contentsOf: fixtures.appendingPathComponent("svglite-\($0).svg"), encoding: .utf8) }
        // Cairo-style glyph references plus deliberately conflicting clip, gradient and CSS names.
        // The second SVG's definitions must never resolve to the first SVG's definitions.
        for (color, path, width) in [("#dd2200", "M10 10H90V90H10Z", 100), ("#0033dd", "M110 10H190V90H110Z", 200)] {
            charts.append("""
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="240" height="120" viewBox="0 0 240 120">
            <defs><style>.paint { fill: \(color); stroke: none; } text { fill: \(color); font-size: 16px; } path { fill: none; } .glyphgroup path { fill: inherit; }</style>
            <g id="glyph-0-1" class="glyphgroup"><path d="\(path)"/></g><clipPath id="clip1"><rect width="\(width)" height="100"/></clipPath>
            <linearGradient id="gradient1"><stop offset="0" stop-color="\(color)"/><stop offset="1" stop-color="white"/></linearGradient></defs>
            <rect width="240" height="120" fill="white"/><g clip-path="url(#clip1)"><use class="paint" xlink:href="#glyph-0-1"/></g>
            <rect y="102" width="240" height="18" fill="url(#gradient1)"/></svg>
            """)
        }
        charts.append(charts[0])
        func open(_ html: String, name: String) async throws -> Document {
            let url = output.appendingPathComponent(name + ".html")
            try ("<!doctype html><html><body>" + html + "</body></html>").write(to: url, atomically: true, encoding: .utf8)
            let report = try await v.importReport(url); try await settled(report)
            return report
        }
        func picture(_ doc: Document, index: Int, name: String) async throws -> NSBitmapImageRep {
            v.tabs.selectTabViewItem(doc.item)
            // A pinned toolbar covers a chart scrolled to the viewport's top.
            // Compare unobscured chart pixels, with geometry measured after scrolling settles.
            _ = try await doc.web.evaluateJavaScript("(()=>{const s=[...document.querySelectorAll('.report-body svg')].filter(s=>!s.parentElement.closest('svg'))[\(index)];s.scrollIntoView({block:'center',behavior:'instant'});})()")
            try await Task.sleep(nanoseconds: 80_000_000)
            let box = try await doc.web.evaluateJavaScript("(()=>{const s=[...document.querySelectorAll('.report-body svg')].filter(s=>!s.parentElement.closest('svg'))[\(index)],b=s.getBoundingClientRect(),bar=document.getElementById('report-toolbar')?.getBoundingClientRect();return {x:b.x,y:b.y,width:b.width,height:b.height,toolbarBottom:bar?.bottom??0,viewportHeight:innerHeight};})()") as! [String: Double]
            precondition(box["y"]! >= max(0, box["toolbarBottom"]!) && box["y"]! + box["height"]! <= box["viewportHeight"]!, "\(name): chart snapshot must fit below the pinned toolbar and inside the viewport")
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: box["x"]!, y: box["y"]!, width: box["width"]!, height: box["height"]!)
            config.snapshotWidth = NSNumber(value: box["width"]!)
            let image = try await doc.web.takeSnapshot(configuration: config)
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
            return bitmap
        }
        func compare(_ left: NSBitmapImageRep, _ right: NSBitmapImageRep, _ name: String) {
            precondition(left.pixelsWide == right.pixelsWide && left.pixelsHigh == right.pixelsHigh, "\(name): chart dimensions differ")
            var different = 0
            for y in 0..<left.pixelsHigh { for x in 0..<left.pixelsWide {
                let a = left.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!, b = right.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                if max(abs(a.redComponent-b.redComponent), abs(a.greenComponent-b.greenComponent), abs(a.blueComponent-b.blueComponent)) > 0.08 { different += 1 }
            } }
            let fraction = Double(different) / Double(left.pixelsWide * left.pixelsHigh)
            precondition(fraction < 0.008, "\(name): \(different) pixels differ (\(fraction)); SVG definitions or styles leaked between charts")
        }
        var expected: [NSBitmapImageRep] = []
        for (index, chart) in charts.enumerated() {
            let single = try await open(chart, name: "r-chart-single-\(index)")
            expected.append(try await picture(single, index: 0, name: "r-chart-reference-\(index)"))
            if index == 2 || index == 3 {
                let bitmap = expected.last!
                var painted = 0
                for y in 0..<(bitmap.pixelsHigh * 3 / 4) { for x in 0..<bitmap.pixelsWide {
                    let c = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    if index == 2 ? c.redComponent > 0.6 && c.blueComponent < 0.3 : c.blueComponent > 0.6 && c.redComponent < 0.3 { painted += 1 }
                } }
                precondition(painted > bitmap.pixelsWide * bitmap.pixelsHigh / 10, "Referenced SVG glyphs retain their shape and stylesheet colour")
            }
        }
        let combined = try await open(charts.joined(), name: "r-charts-combined")
        for index in charts.indices { compare(expected[index], try await picture(combined, index: index, name: "r-chart-combined-\(index)"), "Combined chart \(index)") }
        func localReferences(_ doc: Document) async throws {
            precondition(try await doc.web.evaluateJavaScript("""
            (()=>{const charts=[...document.querySelectorAll('.report-body svg')].filter(s=>!s.parentElement.closest('svg')),ids=charts.flatMap(s=>[...s.querySelectorAll('[id]')].map(n=>n.id));
              return new Set(ids).size===ids.length&&charts.every(s=>[...s.querySelectorAll('*')].every(n=>[...n.attributes].every(a=>{
                const refs=[...a.value.matchAll(/url\\(\\s*["']?#([^)'"\\s]+)["']?\\s*\\)/g)].map(m=>m[1]);
                if(/^(href|xlink:href)$/.test(a.name)&&a.value.startsWith('#'))refs.push(a.value.slice(1));
                return refs.every(id=>!!s.querySelector('[id="'+id+'"]'));
              })));})()
            """) as? Bool == true, "Each imported chart must have its own identifiers and internal references")
        }
        try await localReferences(combined)
        let unsafe = try await ReportImporter.convert(html: "<svg xmlns='http://www.w3.org/2000/svg'><use href='https://example.invalid/chart.svg#glyph'/><use href='data:image/svg+xml,unsafe'/><use href='javascript:alert(1)' onload='alert(1)'/></svg>", resources: v.root)["html"] as! String
        precondition(!unsafe.contains("example.invalid") && !unsafe.contains("javascript:") && !unsafe.contains("onload") && !unsafe.contains("data:image/svg"), "Only local SVG glyph references may survive sanitization")
        for format in ReportFormat.allCases {
            let data = try await v.reportExportData(combined, format: format)
            let url = output.appendingPathComponent("r-charts-roundtrip." + format.rawValue)
            try data.write(to: url)
            if format == .html {
                let reopened = try await v.importReport(url); try await settled(reopened)
                try await localReferences(reopened)
                for index in charts.indices { compare(expected[index], try await picture(reopened, index: index, name: "r-chart-reopened-\(index)"), "Reopened chart \(index)") }
            } else if format == .pdf { precondition((PDFDocument(data: data)?.pageCount ?? 0) > 0, "R charts export to PDF") }
        }
        let pasted = v.makeReport(); try await settled(pasted)
        let board = NSPasteboard(name: .init("StatsDirect-svg-isolation-" + UUID().uuidString))
        board.setString(charts.joined(), forType: .html)
        _ = try await pasted.web.evaluateJavaScript("(()=>{const r=document.getElementById('report-results');r.focus();getSelection().selectAllChildren(r.querySelector('p'));})()")
        precondition(try await v.transferReportClipboard(pasted, command: "paste", pasteboard: board), "Paste the mixed R charts")
        try await settled(pasted)
        try await localReferences(pasted)
        for index in charts.indices { compare(expected[index], try await picture(pasted, index: index, name: "r-chart-pasted-\(index)"), "Pasted chart \(index)") }
        _ = try await pasted.web.evaluateJavaScript("StatsDirectReportEditor.command('undo')"); try await settled(pasted)
        precondition(try await pasted.web.evaluateJavaScript("document.querySelectorAll('.report-body svg').length") as? Int == 0, "Undo removes all pasted charts together")
        _ = try await pasted.web.evaluateJavaScript("StatsDirectReportEditor.command('redo')"); try await settled(pasted)
        try await localReferences(pasted)
        for index in charts.indices { compare(expected[index], try await picture(pasted, index: index, name: "r-chart-redo-\(index)"), "Redo chart \(index)") }
        print("PASS: five imported R/Cairo-style SVGs, repeated charts, independent glyph/clip/gradient/CSS references, pixel comparisons and HTML/PDF/DOCX export"); fflush(stdout)
    }
}
