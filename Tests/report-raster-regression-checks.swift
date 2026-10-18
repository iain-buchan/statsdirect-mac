import Cocoa
import WebKit

extension ReportExportTests {
    // Reproduce a broken default canvas backend while leaving real canvas,
    // PNG encoding and image decoding intact. Only explicit readback contexts
    // can draw; the returned object remains a native 2D context.
    @MainActor static func rasterReadbackRegression(_ v: Viewer, output: URL) async throws {
        let previous = v.active, previousReport = v.activeReportID
        let report = v.makeReport()
        defer {
            v.remove(report)
            if let previous, v.documents.contains(where: { $0 === previous }) { v.tabs.selectTabViewItem(previous.item) }
            v.activeReportID = previousReport
        }
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "RasterReadbackRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func ink(_ data: Data, _ message: String) throws -> Int {
            guard let bitmap = NSBitmapImageRep(data: data) else { throw NSError(domain: "RasterReadbackRegression", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unreadable PNG: " + message]) }
            var count = 0
            for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { throw NSError(domain: "RasterReadbackRegression", code: 3, userInfo: [NSLocalizedDescriptionKey: "PNG colour conversion failed: " + message]) }
                if color.alphaComponent > 0 && min(color.redComponent, color.greenComponent, color.blueComponent) < 0.95 { count += 1 }
            } }
            return count
        }
        func png(_ url: String) throws -> Data {
            guard url.hasPrefix("data:image/png;base64,"), let data = Data(base64Encoded: String(url.dropFirst("data:image/png;base64,".count))) else { throw NSError(domain: "RasterReadbackRegression", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected an encoded PNG"]) }
            return data
        }
        func js(_ script: String, world: WKContentWorld) async throws -> Any {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any, Error>) in
                report.web.callAsyncJavaScript(script, arguments: [:], in: nil, in: world) { continuation.resume(with: $0) }
            }
        }
        let source = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<10 { for x in 0..<20 { source.setColor(NSColor(deviceRed: 0.8, green: 0.1, blue: 0.2, alpha: 1), atX: x, y: y) } }
        let sourcePNG = source.representation(using: .png, properties: [:])!
        try require(try ink(sourcePNG, "source fixture") == 200, "The raster fixture must contain 200 coloured pixels")
        let vector = "<svg id='readback-svg' xmlns='http://www.w3.org/2000/svg' width='100' height='40' viewBox='0 0 100 40'><rect width='100' height='40' fill='#237040'/></svg>"
        report.reportEntries = [ReportEntry(id: "readback-result", title: "Raster readback", operation: "", body: "<h1>Raster readback</h1>" + vector + "<img alt='Known raster' src='data:image/png;base64," + sourcePNG.base64EncodedString() + "'>", record: nil)]
        v.renderReport(report)
        try await settled(report)
        let install = #"""
        if(window.__statsDirectReadbackFault)throw new Error('Canvas fault already installed');
        const proto=HTMLCanvasElement.prototype,descriptor=Object.getOwnPropertyDescriptor(proto,'getContext'),original=descriptor.value;
        const modes=new WeakMap(),counts={default:0,frequent:0};
        Object.defineProperty(proto,'getContext',{...descriptor,value:function(type,options,...rest){
          const context=original.call(this,type,options,...rest);
          if(type==='2d'&&context&&!modes.has(this)){
            const frequent=options?.willReadFrequently===true;modes.set(this,frequent);counts[frequent?'frequent':'default']++;
            if(!frequent){context.fillRect=function(){};context.drawImage=function(){};}
          }
          return context;
        }});
        window.__statsDirectReadbackFault={counts,restore(){Object.defineProperty(proto,'getContext',descriptor);delete window.__statsDirectReadbackFault;}};
        const controls=[];
        for(const frequent of [false,true]){
          const canvas=document.createElement('canvas');canvas.width=20;canvas.height=10;
          const context=canvas.getContext('2d',frequent?{willReadFrequently:true}:undefined);
          if(!(context instanceof CanvasRenderingContext2D)||context.canvas!==canvas)throw new Error('Fault replaced native canvas context type');
          context.fillStyle='#cc1933';context.fillRect(0,0,20,10);controls.push(canvas.toDataURL('image/png'));
        }
        return controls;
        """#
        func restore() async {
            for world in [WKContentWorld.page, .defaultClient] { _ = try? await js("window.__statsDirectReadbackFault?.restore();return true;", world: world) }
        }
        do {
            // Native report export executes in defaultClient, while the editor
            // executes in page. Patch and validate the fault in both worlds.
            for world in [WKContentWorld.page, .defaultClient] {
                let controls = try await js(install, world: world) as? [String] ?? []
                try require(controls.count == 2, "Canvas controls did not execute")
                try require(try ink(png(controls[0]), "default negative control") == 0, "Default canvas fault did not reproduce transparent output")
                try require(try ink(png(controls[1]), "readback positive control") == 200, "Readback canvas positive control is blank")
            }
            let editorPNG = try await js("document.getElementById('readback-svg').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true}));return await StatsDirectReportEditor.chartImage('png',2);", world: .page) as? String ?? ""
            try require(try ink(png(editorPNG), "Save Chart PNG") > 50, "Save Chart PNG used the broken default canvas")
            guard let clipboard = try await v.reportScript(report, method: "clipboard", fragment: vector, nativeImage: true),
                  let captured = try JSONSerialization.jsonObject(with: Data(clipboard.utf8)) as? [String: Any],
                  let image = captured["image"] as? [String: Any], let clipboardPNG = image["png"] as? String else { throw NSError(domain: "RasterReadbackRegression", code: 5, userInfo: [NSLocalizedDescriptionKey: "SVG copy returned no native PNG"]) }
            try require((image["svg"] as? String)?.contains("<svg") == true, "SVG copy lost its vector representation")
            try require(try ink(png(clipboardPNG), "SVG clipboard fallback") > 50, "SVG clipboard PNG used the broken default canvas")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let archive = output.appendingPathComponent("raster-readback-report.docx")
            try await v.reportExportData(report, format: .docx).write(to: archive)
            let extracted = FileManager.default.temporaryDirectory.appendingPathComponent("sd-raster-readback-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: extracted) }
            let unzip = Process(), pipe = Pipe()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-qq", archive.path, "-d", extracted.path]
            unzip.standardOutput = pipe; unzip.standardError = pipe
            try unzip.run(); let diagnostic = pipe.fileHandleForReading.readDataToEndOfFile(); unzip.waitUntilExit()
            try require(unzip.terminationStatus == 0, "Cannot inspect actual DOCX: " + String(decoding: diagnostic, as: UTF8.self))
            let media = try FileManager.default.contentsOfDirectory(at: extracted.appendingPathComponent("word/media"), includingPropertiesForKeys: nil)
            let pngs = media.filter { $0.pathExtension.lowercased() == "png" }
            try require(pngs.count == 2 && media.filter { $0.pathExtension.lowercased() == "svg" }.count == 1, "DOCX must retain one SVG fallback and one raster input")
            for file in pngs { try require(try ink(Data(contentsOf: file), file.lastPathComponent) > 50, "DOCX contains a blank PNG: " + file.lastPathComponent) }
            for world in [WKContentWorld.page, .defaultClient] {
                let counts = try await js("return window.__statsDirectReadbackFault.counts;", world: world) as? [String: Int] ?? [:]
                try require(counts["default"] == 1 && (counts["frequent"] ?? 0) >= 2, "Production export requested a default canvas: \(counts)")
            }
        } catch {
            await restore()
            throw error
        }
        await restore()
        print("PASS: forced default-canvas failure leaves editor PNG, native SVG copy fallback and both actual DOCX PNG media nonblank; contexts restored")
        fflush(stdout)
    }
}
