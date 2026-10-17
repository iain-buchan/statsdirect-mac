import Cocoa
import WebKit

extension ReportExportTests {
    @MainActor static func imageEditing(_ v: Viewer, output: URL) async throws {
        let report = v.makeReport()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<80 { for x in 0..<120 {
            let offset = y * bitmap.bytesPerRow + x * 4
            bitmap.bitmapData![offset] = 255; bitmap.bitmapData![offset + 1] = 0
            bitmap.bitmapData![offset + 2] = 0; bitmap.bitmapData![offset + 3] = 255
        } }
        let png = bitmap.representation(using: .png, properties: [:])!, tiff = bitmap.representation(using: .tiff, properties: [:])!
        let pixel = "data:image/png;base64," + png.base64EncodedString()
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='120' height='80' viewBox='0 0 120 80'><path d='M5 5H115V75H5Z' fill='red'/></svg>"
        let record = #"{"version":1,"operation":"TPaired","title":"Picture result","run":"2026-10-17T09:00:00+01:00","inputs":[],"parameters":{"gamma":0.95},"values":{"marker":17}}"#
        func js(_ source: String) async throws -> Any { try await report.web.evaluateJavaScript(source) ?? NSNull() }
        func check(_ source: String, _ reason: String) async throws {
            let ok = try await js(source) as? Bool == true
            if !ok { print("Image editing:", reason, try await js("document.getElementById('report-results').innerHTML")); fflush(stdout) }
            precondition(ok, reason)
        }
        func reset(_ picture: String) async throws {
            report.reportEntries = [ReportEntry(id: "image-before", title: "Earlier", operation: "", body: "<p>Earlier result</p>", record: nil),
                ReportEntry(id: "image-result", title: "Picture", operation: "TPaired", body: picture, record: record, recipe: true, helpPath: "Help/parametric_methods/paired_t.htm"),
                ReportEntry(id: "image-after", title: "Following", operation: "", body: "<p>Following result</p>", record: nil)]
            report.reportUndo = []; report.reportRedo = []; report.reportEditing = true
            v.renderReport(report); try await settled(report)
        }
        func caret(_ selector: String, after: Bool = false, offset: Int? = nil) async throws {
            let placement = after ? "r.setStartAfter(p);r.collapse(true);" : offset.map { "r.setStart(p.firstChild,\($0));r.collapse(true);" } ?? "r.selectNodeContents(p);r.collapse(false);"
            _ = try await js("(()=>{const p=document.querySelector(\(v.jsString(selector))),r=document.createRange();document.getElementById('report-results').focus();\(placement)getSelection().removeAllRanges();getSelection().addRange(r);})()")
        }
        func native(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) async throws {
            v.window.makeKeyAndOrderFront(nil); v.window.makeFirstResponder(report.web)
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: v.window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters.lowercased(), isARepeat: false, keyCode: code)!
            v.window.sendEvent(event); try await settled(report)
        }
        func clickPicture(_ selector: String) async throws {
            v.tabs.selectTabViewItem(report.item); v.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true); v.window.makeFirstResponder(report.web)
            _ = try await js("window.__pictureClicks=[];for(const t of ['pointerdown','pointerup','click'])document.addEventListener(t,e=>window.__pictureClicks.push({type:t,target:e.target.tagName,cls:e.target.className?.baseVal||e.target.className,x:e.clientX,y:e.clientY,trusted:e.isTrusted}),{capture:true,once:true});")
            _ = try await js("document.querySelector(\(v.jsString(selector))).scrollIntoView({block:'center'})")
            try await Task.sleep(nanoseconds: 100_000_000)
            let box = try await js("(()=>{const b=document.querySelector(\(v.jsString(selector))).getBoundingClientRect();return {x:b.x+b.width/2,y:b.y+b.height/2};})()") as! [String: Double]
            let point = report.web.convert(NSPoint(x: box["x"]!, y: report.web.isFlipped ? box["y"]! : report.web.bounds.height - box["y"]!), to: nil)
            // The test window can remain behind the user's app. Deliver native
            // events to its hit-tested WebKit view, avoiding NSWindow's first
            // activation click; WebKit still creates trusted pointer events.
            let target = report.web.hitTest(report.web.superview!.convert(point, from: nil))!
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: v.window.windowNumber, context: nil, eventNumber: 10, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                if type == .leftMouseDown { target.mouseDown(with: event) } else { target.mouseUp(with: event) }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            if try await js("!!StatsDirectReportEditor.selectedPicture()&&!getSelection().isCollapsed") as? Bool != true {
                print("Native picture click:", box, point, "flipped", report.web.isFlipped, "web frame", report.web.frame, "key", v.window.isKeyWindow, "events", try await js("JSON.stringify(window.__pictureClicks)")); fflush(stdout)
            }
            try await check("!!StatsDirectReportEditor.selectedPicture()&&!getSelection().isCollapsed", "A native mouse click retains the picture selection after pointer capture and click")
            try await check("window.__pictureClicks.some(e=>e.type==='pointerdown'&&e.trusted)&&window.__pictureClicks.some(e=>e.type==='pointerup'&&e.trusted)", "Picture check uses trusted native WebKit pointer events")
        }
        let paragraph = "document.querySelector('#result-image-result .report-media').nextElementSibling"
        for (kind, picture) in [("SVG", svg), ("PNG", "<img width='120' height='80' src='\(pixel)'>")] {
            try await reset("<p>Original finding</p>" + picture)
            try await caret("#result-image-result .report-media", after: true)
            try await native("\r", code: 36)
            try await check("(()=>{const p=\(paragraph);return p?.tagName==='P'&&p.isContentEditable&&!p.closest('[contenteditable=false]')&&p.contains(getSelection().anchorNode);})()", "\(kind) native Enter makes an editable paragraph")
            precondition(report.reportEntries!.map(\.id) == ["image-before", "image-result", "image-after"] && report.reportEntries![1].record == record && report.reportEntries![1].helpPath != nil && report.reportUndo.count == 1, "Enter preserves result identity, Help, record and a single undo")
            try await native("z", code: 6, flags: .command)
            try await check("document.querySelectorAll('#result-image-result > p').length===1&&!!document.querySelector('#result-image-result .report-media')", "Command-Z undoes only the new paragraph")
            try await native("z", code: 6, flags: [.command, .shift])
            try await caret("#result-image-result .report-media + p")
            try await native("X", code: 7)
            try await check("\(paragraph).textContent==='X'", "Native typing stays in the new paragraph")
            try await native("z", code: 6, flags: .command)
            try await check("\(paragraph)?.tagName==='P'&&\(paragraph).textContent===''", "Typing undo is separate from Enter")
            try await native("z", code: 6, flags: [.command, .shift])
            let saved = output.appendingPathComponent("image-enter-\(kind).html")
            try await v.reportExportData(report, format: .html).write(to: saved)
            let reopened = try await v.importReport(saved); try await settled(reopened)
            precondition(reopened.reportEntries?.count == 3 && reopened.reportEntries?[1].record == record && reopened.reportEntries?[1].helpPath != nil, "Picture Enter metadata survives saving and reopening")
            precondition(try await reopened.web.evaluateJavaScript("document.querySelector('.report-media + p').textContent==='X'") as? Bool == true)
            v.remove(reopened); v.tabs.selectTabViewItem(report.item)
            try await reset(picture + "<p>Existing text</p>")
            _ = try await js("document.querySelector('#result-image-result \(kind == "SVG" ? "svg" : "img")').dispatchEvent(new MouseEvent('click',{bubbles:true}))")
            try await native("\r", code: 36); try await native("X", code: 7)
            try await check("\(paragraph).textContent==='X'&&\(paragraph).nextElementSibling.textContent==='Existing text'", "Selected picture Enter retains following text")
        }
        for (html, selector, condition) in [
            ("<div class='report-chart' contenteditable='false'>\(svg)</div>", ".report-chart", "p.parentElement===e&&!p.closest('[contenteditable=false]')"),
            ("<p><img src='\(pixel)'></p>", "p", "p.parentElement===e&&!e.querySelector('p p')"),
            ("<table><tr><td>\(svg)</td><td>Other cell</td></tr></table>", ".report-media", "p.parentElement.tagName==='TD'&&p.parentElement.nextElementSibling.textContent==='Other cell'")
        ] {
            try await reset(html); try await caret("#result-image-result .report-media", after: true); try await native("\r", code: 36)
            try await check("(()=>{const e=document.getElementById('result-image-result'),p=e.querySelector('\(selector)').nextElementSibling;return p?.tagName==='P'&&p.isContentEditable&&\(condition);})()", "Enter escapes picture wrappers and stays inside table cells")
        }
        try await reset(svg + "<p>AlphaOmega</p>"); try await caret("#result-image-result > p", offset: 5); try await native("\r", code: 36)
        try await check("(()=>{const p=document.querySelectorAll('#result-image-result > p');return p.length===2&&p[0].textContent==='Alpha'&&p[1].textContent==='Omega';})()", "Native ordinary text Enter still splits the paragraph")
        try await reset(svg); try await caret("#result-image-after p", offset: 0); try await native("\r", code: 36)
        try await check("!document.querySelector('#result-image-result p')", "Enter in following result does not modify the chart result")
        try await reset(svg); try await caret("#result-image-result .report-media", after: true)
        try await check("(()=>{const e=document.getElementById('result-image-result'),html=e.innerHTML;for(const flags of [{shiftKey:true},{ctrlKey:true},{altKey:true},{metaKey:true},{isComposing:true}]){const k=new KeyboardEvent('keydown',{key:'Enter',bubbles:true,cancelable:true,...flags});document.getElementById('report-results').dispatchEvent(k);if(k.defaultPrevented||e.innerHTML!==html)return false;}return true;})()", "Modified/composing Enter is left to WebKit")
        _ = try await js("StatsDirectReportEditor.setEditing(false)"); try await native("\r", code: 36)
        try await check("!document.querySelector('#result-image-result p')", "Reading mode cannot insert paragraphs")
        _ = try await js("StatsDirectReportEditor.setEditing(true)"); try await caret("#result-image-result .report-media", after: true)
        _ = try await js("document.getElementById('report-results').dispatchEvent(new InputEvent('beforeinput',{inputType:'insertParagraph',bubbles:true,cancelable:true}))")
        try await settled(report); try await check("\(paragraph)?.tagName==='P'", "Non-keyboard paragraph input works")
        print("PASS: native WebKit Enter/typing, selected SVG/PNG, protected and terminal pictures, picture paragraphs/table cells, Command-Z/Shift-Command-Z, guards and metadata save/reopen"); fflush(stdout)

        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let doctype = "<?xml version='1.0'?><!DOCTYPE svg PUBLIC '-//W3C//DTD SVG 1.1//EN' 'https://invalid.example/svg.dtd'>" + svg
        let variants: [(String, NSPasteboard.PasteboardType, Data)] = [
            ("SVG", ReportImageClipboard.svgTypes[0], Data(svg.utf8)),
            ("MIME SVG", ReportImageClipboard.svgTypes[1], Data(svg.utf8)),
            ("UTF8 BOM", ReportImageClipboard.svgTypes[0], Data([0xef, 0xbb, 0xbf]) + Data(doctype.utf8)),
            ("UTF16 BOM", ReportImageClipboard.svgTypes[1], doctype.data(using: .utf16)!),
            ("PNG", .png, png), ("TIFF bitmap", .tiff, tiff)]
        for (name, type, data) in variants {
            for blank in [false, true] {
                if blank { report.reportEntries = []; report.reportUndo = []; report.reportRedo = []; v.renderReport(report); try await settled(report) }
                else { try await reset("<p>Existing text</p>") }
                try await caret(blank ? "#report-results p" : "#result-image-result p")
                board.clearContents(); board.setData(data, forType: type)
                _ = try await v.transferReportClipboard(report, command: "paste", pasteboard: board); try await settled(report)
                let vector = ReportImageClipboard.svgTypes.contains(type)
                try await check(vector ? "document.querySelectorAll('#report-results svg path').length===1" : "document.querySelectorAll('#report-results img[src^=\"data:image/png\"]').length===1", "\(name) pastes into \(blank ? "a blank report" : "existing text")")
                precondition(report.reportUndo.count == 1, "Image paste is one undo transaction")
                _ = try await js("StatsDirectReportEditor.command('undo')"); try await settled(report)
                try await check("!document.querySelector('#report-results svg,#report-results img')", "Picture paste undoes")
                _ = try await js("StatsDirectReportEditor.command('redo')"); try await settled(report)
                let file = output.appendingPathComponent("image-clipboard-\(name.replacingOccurrences(of: " ", with: "-"))-\(blank).html")
                try await v.reportExportData(report, format: .html).write(to: file)
                let reopened = try await v.importReport(file); try await settled(reopened)
                precondition(try await reopened.web.evaluateJavaScript(vector ? "!!document.querySelector('.report-media svg path')" : "!!document.querySelector('.report-media img[src^=\"data:image/png\"]')") as? Bool == true, "Pasted image bytes survive saved HTML")
                v.remove(reopened); v.tabs.selectTabViewItem(report.item)
            }
        }
        // A native SVG must win over raster HTML intended for Office. Our own
        // private rich fragment still wins over every image representation.
        try await reset("<p>Destination</p>"); try await caret("#result-image-result p")
        board.clearContents(); board.setData(Data(svg.utf8), forType: ReportImageClipboard.svgTypes[0]); board.setString("<img src='\(pixel)'>", forType: .html); board.setData(png, forType: .png)
        _ = try await v.transferReportClipboard(report, command: "paste", pasteboard: board); try await settled(report)
        try await check("!!document.querySelector('#result-image-result svg')&&!document.querySelector('#result-image-result img')", "SVG wins over raster Office HTML")
        try await reset("<p>Destination</p>"); try await caret("#result-image-result p")
        board.setString("<strong>Private selection</strong>", forType: Viewer.reportFragmentType)
        _ = try await v.transferReportClipboard(report, command: "paste", pasteboard: board); try await settled(report)
        try await check("document.querySelector('#result-image-result strong').textContent==='Private selection'&&!document.querySelector('#result-image-result svg')", "Private rich fragment retains priority")
        // Bad input must not consume the selection or create undo entries.
        try await reset("<p>Unchanged</p>"); try await caret("#result-image-result p")
        for (type, bytes) in [(ReportImageClipboard.svgTypes[0], Data("<html/>".utf8)), (.png, Data("invalid png".utf8)), (ReportImageClipboard.svgTypes[0], Data(repeating: 32, count: ReportImageClipboard.maximumBytes + 1))] {
            board.clearContents(); board.setData(bytes, forType: type)
            var rejected = false
            do { _ = try await v.transferReportClipboard(report, command: "paste", pasteboard: board) } catch { rejected = true }
            precondition(rejected && report.reportUndo.isEmpty, "Malformed/oversized clipboard data must be rejected without mutation")
        }
        print("PASS: SVG-only/UTF8/UTF16/legacy DOCTYPE/PNG/TIFF paste, blank/existing reports, vector priority, undo/redo, self-contained HTML reopen and malformed/size guards"); fflush(stdout)

        let originalFrame = v.window.frame
        let viewportHeight = try await js("window.innerHeight") as! Double
        var shortFrame = originalFrame; shortFrame.size.height += 158 - viewportHeight
        v.window.setFrame(shortFrame, display: true)
        try await settled(report)
        try await check("window.innerHeight<=180", "Native picture click is checked in a short report viewport")
        for (kind, picture) in [("svg", svg), ("img", "<img width='120' height='80' src='\(pixel)'>")] {
            try await reset("<p>Caption retained</p>" + picture)
            for command in ["copy", "cut"] {
                try await clickPicture("#result-image-result \(kind)")
                _ = try await v.transferReportClipboard(report, command: command, pasteboard: board); try await settled(report)
                precondition(board.data(forType: .png) != nil && NSImage(pasteboard: board)?.size.width ?? 0 > 0, "Selected report picture offers a native image consumer format")
                precondition(NSBitmapImageRep(data: board.data(forType: .png)!)?.pixelsWide ?? 0 > 0, "Report clipboard PNG decodes")
                precondition((board.data(forType: ReportImageClipboard.svgTypes[0]) != nil) == (kind == "svg"), "Report SVG copy retains vector format, raster copy stays raster")
                precondition(board.string(forType: Viewer.reportFragmentType) != nil && board.string(forType: .html) != nil, "Native image formats supplement existing report clipboard formats")
                if command == "cut" {
                    try await check("!document.querySelector('#result-image-result \(kind)')&&document.getElementById('result-image-result').textContent==='Caption retained'", "Cut removes only its published picture")
                    precondition(report.reportUndo.count == 1)
                    _ = try await js("StatsDirectReportEditor.command('undo')"); try await settled(report)
                    try await check("!!document.querySelector('#result-image-result \(kind)')", "Picture Cut undoes")
                } else { precondition(report.reportUndo.isEmpty, "Picture Copy does not edit the report") }
            }
            _ = try await js("(()=>{const e=document.getElementById('result-image-result'),r=document.createRange();document.getElementById('report-results').focus();r.selectNodeContents(e);getSelection().removeAllRanges();getSelection().addRange(r);})()")
            _ = try await v.transferReportClipboard(report, command: "copy", pasteboard: board)
            precondition(board.data(forType: .png) == nil && board.data(forType: ReportImageClipboard.svgTypes[0]) == nil && board.string(forType: Viewer.reportFragmentType)?.contains("Caption retained") == true, "Mixed report copies keep rich text/table semantics without advertising a single picture")
            let mixed = try await v.reportScript(report, method: "clipboard", fragment: board.string(forType: Viewer.reportFragmentType)!, nativeImage: true)!
            let formats = try JSONSerialization.jsonObject(with: Data(mixed.utf8)) as! [String: Any]
            precondition(formats["image"] == nil, "Immutable fragment classification rejects native image formats for mixed content")
        }
        v.window.setFrame(originalFrame, display: true); try await settled(report)
        print("PASS: single report SVG/PNG Copy and Cut offer readable native images plus rich formats; Cut/undo and mixed selections retain their semantics"); fflush(stdout)

        // Real native SVG paste must keep repeated glyph/gradient/clip IDs and
        // per-SVG styles independent, including the rendered saved/reopened view.
        try await reset("<p>Two pasted charts</p>")
        for color in ["red", "blue"] {
            let chart = """
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="80" height="80" viewBox="0 0 80 80">
            <defs><style>.paint { fill:url(#paint); }</style><linearGradient id="paint"><stop stop-color="\(color)"/><stop offset="1" stop-color="\(color)"/></linearGradient>
            <clipPath id="clip"><rect width="80" height="80"/></clipPath><g id="glyph"><path d="M0 0H80V80H0Z"/></g></defs>
            <g clip-path="url(#clip)"><use class="paint" xlink:href="#glyph"/></g></svg>
            """
            try await caret("#result-image-result")
            board.clearContents(); board.setData(Data(chart.utf8), forType: ReportImageClipboard.svgTypes[0])
            _ = try await v.transferReportClipboard(report, command: "paste", pasteboard: board); try await settled(report)
        }
        try await check("(()=>{const ids=[...document.querySelectorAll('#result-image-result svg [id]')].map(e=>e.id);return ids.length===6&&new Set(ids).size===6;})()", "Pasted SVG IDs are isolated")
        func colors(_ doc: Document) async throws {
            v.tabs.selectTabViewItem(doc.item)
            for index in 0..<2 {
                let box = try await doc.web.evaluateJavaScript("(()=>{const p=document.querySelectorAll('.report-media > svg')[\(index)];p.scrollIntoView({block:'center'});const r=p.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height};})()") as! [String: Double]
                try await Task.sleep(nanoseconds: 100_000_000)
                let config = WKSnapshotConfiguration(); config.rect = NSRect(x: box["x"]!, y: box["y"]!, width: box["w"]!, height: box["h"]!)
                let capture = try await doc.web.takeSnapshot(configuration: config)
                let bitmap = NSBitmapImageRep(data: capture.tiffRepresentation!)!
                let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
                precondition(index == 0 ? color.redComponent > 0.8 && color.blueComponent < 0.2 : color.blueComponent > 0.8 && color.redComponent < 0.2, "Pasted chart \(index) lost its own paint/glyph/clip")
            }
        }
        try await colors(report)
        _ = try await js("StatsDirectReportEditor.command('undo')"); try await settled(report)
        try await check("document.querySelectorAll('#result-image-result svg').length===1", "Second chart paste undoes independently")
        _ = try await js("StatsDirectReportEditor.command('redo')"); try await settled(report); try await colors(report)
        let pairedFile = output.appendingPathComponent("native-pasted-svg-pair.html")
        try await v.reportExportData(report, format: .html).write(to: pairedFile)
        let pair = try await v.importReport(pairedFile); try await settled(pair); try await colors(pair)
        v.remove(pair); v.tabs.selectTabViewItem(report.item)

        let marker = "External entity must remain unread " + UUID().uuidString
        let privateFile = output.appendingPathComponent("external-entity-fixture.txt")
        try marker.write(to: privateFile, atomically: true, encoding: .utf8)
        let entity = "<!DOCTYPE svg [<!ENTITY external SYSTEM '\(privateFile.absoluteString)'>]><svg xmlns='http://www.w3.org/2000/svg'><text>&external;</text></svg>"
        if let parsed = try? ReportImageClipboard.svgMarkup(Data(entity.utf8)) { precondition(!parsed.contains(marker), "Native SVG parsing must never resolve external entities") }
        try await reset("<p>Safe destination</p>"); try await caret("#result-image-result p")
        board.clearContents(); board.setData(Data("<svg xmlns='http://www.w3.org/2000/svg' onload='alert(1)'><script>alert(1)</script><foreignObject><div>active</div></foreignObject><image href='https://invalid.example/picture'/><path d='M0 0H20'/></svg>".utf8), forType: ReportImageClipboard.svgTypes[0])
        _ = try await v.transferReportClipboard(report, command: "paste", pasteboard: board); try await settled(report)
        try await check("!!document.querySelector('#result-image-result svg path')&&!document.querySelector('#result-image-result script,#result-image-result foreignObject,#result-image-result [onload],#result-image-result [href^=\"https:\"]')", "Native SVG goes through the existing offline sanitizer")
        print("PASS: two native SVG pastes render independently across undo/redo and HTML reopen; external entities/active SVG stay blocked"); fflush(stdout)

        // Copy image dispatch in the actual R output view, then the report's
        // native Paste action. Preserve the user's general pasteboard afterwards.
        func require(_ ok: Bool, _ reason: String = "R clipboard check failed") throws {
            if !ok { throw LegacyReportError(reason) }
        }
        let general = NSPasteboard.general
        let savedClipboard = general.pasteboardItems?.map { item in item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) } } ?? []
        defer {
            general.clearContents(); general.writeObjects(savedClipboard.map { values in
                let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item
            })
        }
        let pane = RPane(resources: v.root)
        defer { pane.shutdown() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = pane.view; window.makeKeyAndOrderFront(nil); pane.view.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(nanoseconds: 100_000_000)
        pane.editor.string = "alpha beta"; pane.editor.setSelectedRange(NSRange(location: 0, length: 5)); window.makeFirstResponder(pane.editor)
        let codePoint = pane.editor.convert(NSPoint(x: 20, y: 20), to: nil)
        let codeEvent = NSEvent.mouseEvent(with: .rightMouseDown, location: codePoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let codeMenu = pane.editor.menu(for: codeEvent)
        for selector in ["cut:", "copy:", "paste:"] {
            try require(codeMenu?.items.contains { $0.action == NSSelectorFromString(selector) } == true, "R code retains native \(selector) context command")
        }
        try require(pane.editor.selectedRange() == NSRange(location: 0, length: 5), "Opening the code context menu preserves selection")
        let cutCode = codeMenu!.items.first { $0.action == #selector(NSText.cut(_:)) }!
        // This isolated window may remain behind the user's active app. Resolve
        // nil menu targets through its real first responder, not NSApp.keyWindow.
        let cutSent = NSApp.sendAction(cutCode.action!, to: cutCode.target ?? window.firstResponder, from: cutCode)
        try await Task.sleep(nanoseconds: 100_000_000)
        try require(cutSent && pane.editor.string == " beta", "Native R code Cut menu dispatch: sent=\(cutSent), text=\(pane.editor.string), selection=\(pane.editor.selectedRange()), key=\(window.isKeyWindow), focus=\(String(describing: window.firstResponder)), target=\(String(describing: cutCode.target))")
        let pasteCode = codeMenu!.items.first { $0.action == #selector(NSText.paste(_:)) }!
        let pasteSent = NSApp.sendAction(pasteCode.action!, to: pasteCode.target ?? window.firstResponder, from: pasteCode)
        try await Task.sleep(nanoseconds: 100_000_000)
        try require(pasteSent && pane.editor.string == "alpha beta", "Native R code Paste menu dispatch")
        print("PASS: R code retains native Cut/Copy/Paste context commands, selection and action dispatch"); fflush(stdout)
        func run(_ script: String, timeout: TimeInterval = 40) async throws -> Int {
            pane.editor.string = script; pane.runScript()
            let deadline = Date().addingTimeInterval(timeout)
            while pane.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
            try require(!pane.isRunning && !pane.console.string.contains("Error:"), "R clipboard fixture completes")
            var positions = [Int]()
            pane.console.textStorage!.enumerateAttribute(.attachment, in: NSRange(location: 0, length: pane.console.textStorage!.length)) { value, range, _ in if value != nil { positions.append(range.location) } }
            try require(!positions.isEmpty, "R output contains a chart")
            return positions.last!
        }
        // The standalone report suite can run before the engine/R suite has
        // installed the program's report graphics package on a clean runner.
        let index = try await run("if (!requireNamespace('svglite', quietly=TRUE)) install.packages('svglite', repos='https://cloud.r-project.org', lib=.libPaths()[1]); svglite::svglite('clipboard-vector.svg'); plot(1:3, main='Original vector'); dev.off(); stopifnot(file.exists('clipboard-vector.svg'))", timeout: 180)
        pane.console.scrollRangeToVisible(NSRange(location: index, length: 1)); pane.view.layoutSubtreeIfNeeded()
        pane.console.layoutManager!.ensureLayout(for: pane.console.textContainer!)
        let glyphs = pane.console.layoutManager!.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let rect = pane.console.layoutManager!.boundingRect(forGlyphRange: glyphs, in: pane.console.textContainer!)
        let point = pane.console.convert(NSPoint(x: rect.midX + pane.console.textContainerOrigin.x, y: rect.midY + pane.console.textContainerOrigin.y), to: nil)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let menu = pane.console.menu(for: event)
        let copy = menu?.items.first { $0.title == "Copy image" }
        try require(copy != nil && NSApp.sendAction(copy!.action!, to: copy!.target, from: copy!), "Native R output Copy image menu dispatch")
        let vector = general.data(forType: ReportImageClipboard.svgTypes[0])
        try require(vector != nil && general.data(forType: .png) != nil, "R Copy image offers SVG plus Office PNG fallback: types=\(general.types ?? []), status=\(pane.state.stringValue), output=\(pane.console.string)")
        try require(NSBitmapImageRep(data: general.data(forType: .png)!) != nil)
        try "<svg xmlns='http://www.w3.org/2000/svg'/>".write(to: pane.outputFolder!.appendingPathComponent("clipboard-vector.svg"), atomically: true, encoding: .utf8)
        pane.console.setSelectedRange(NSRange(location: index, length: 1)); pane.console.copy(nil)
        try require(general.data(forType: ReportImageClipboard.svgTypes[0]) == vector, "R Copy keeps original vector bytes after file overwrite")
        try await reset("<p>R interpretation</p>"); try await caret("#result-image-result p")
        v.window.makeKeyAndOrderFront(nil); v.tabs.selectTabViewItem(report.item)
        let paste = NSMenuItem(title: "Paste", action: #selector(Viewer.editCommand(_:)), keyEquivalent: "v"); paste.representedObject = "paste"
        v.editCommand(paste)
        for _ in 0..<100 where report.reportUndo.isEmpty { try await Task.sleep(nanoseconds: 50_000_000) }
        try await check("document.querySelectorAll('#result-image-result svg circle').length===3&&document.querySelector('#result-image-result svg').textContent.includes('Original vector')&&!document.querySelector('#result-image-result img')", "R copy to native report Paste retains vector geometry and labels")
        try await clickPicture("#result-image-result svg")
        let copyReport = NSMenuItem(title: "Copy", action: #selector(Viewer.editCommand(_:)), keyEquivalent: "c"); copyReport.representedObject = "copy"
        let previousChange = general.changeCount
        v.editCommand(copyReport)
        for _ in 0..<100 where general.changeCount == previousChange { try await Task.sleep(nanoseconds: 50_000_000) }
        try require(general.string(forType: Viewer.reportFragmentType) != nil && general.data(forType: .png) != nil && general.data(forType: ReportImageClipboard.svgTypes[0]) != nil && NSImage(pasteboard: general) != nil, "Native report Copy menu retains vector and native image formats after a real picture click")
        let pdfIndex = try await run("plot(1:3, main='Ordinary PDF')")
        try require(try pane.copyPlot(at: pdfIndex, to: board) && board.data(forType: .png) != nil && board.data(forType: ReportImageClipboard.svgTypes[0]) == nil, "Ordinary PDF chart offers a readable PNG copy without changing its output format")
        print("PASS: real R SVG Copy image menu/selection, PNG fallback, original-byte snapshot, native report Paste and ordinary PDF image copying"); fflush(stdout)
        v.remove(report)
    }
}
