import Cocoa
import PDFKit

@main
struct RPaneChecks {
    private static func precondition(_ condition: Bool, _ message: @autoclosure () -> String = "R pane assertion failed") {
        guard condition else { print("FAIL: " + message()); fflush(stdout); exit(1) }
    }
    @MainActor static func main() throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        _ = NSApplication.shared
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let pane = RPane(resources: resources)
        pane.view.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
        pane.view.layoutSubtreeIfNeeded()
        defer { pane.shutdown() }
        precondition(pane.console.textLayoutManager == nil && pane.console.layoutManager != nil,
                     "Plot output uses the attachment-compatible text layout system before its first run")
        func images(_ target: RPane) -> [NSTextAttachment] {
            var found = [NSTextAttachment]()
            let storage = target.console.textStorage!
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                if let attachment = value as? NSTextAttachment { found.append(attachment) }
            }
            return found
        }
        func wait(_ targets: [RPane]) {
            let deadline = Date().addingTimeInterval(30)
            while targets.contains(where: \.isRunning) && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            for target in targets { precondition(!target.isRunning && target.state.stringValue.contains("Ready"), target.state.stringValue) }
        }
        func run(_ script: String, plots: Int) {
            let before = images(pane).count
            pane.editor.string = script; pane.runScript()
            precondition(pane.isRunning, pane.state.stringValue)
            wait([pane])
            precondition(images(pane).count == before + plots, "Expected \(plots) new plots.\n" + pane.console.string)
        }
        run("stopifnot(!'svglite' %in% loadedNamespaces()); x <- 1:5\nplot(x, x^2, main='First plot')\nplot(x, rev(x), main='Second plot')", plots: 2)
        precondition(images(pane).allSatisfy { ($0.image?.size.width ?? 0) > 0 })
        run("stopifnot(identical(x, 1:5)); cat('Variables retained\\n')", plots: 0)
        run("plot(x, x * 2); stop('Deliberate test error')", plots: 1)
        precondition(pane.console.string.contains("Error: Deliberate test error"))
        run("plot(x); dev.off(); plot(x, -x)", plots: 2)
        print("PASS default plots, multiple pages/devices, errors and variables across runs")
        // Output longer than the pane must be reachable: the console grows beyond its visible height and shows its end after a
        // run, as the editor does (a text view built on an explicit TextKit 1 stack starts with a zero maximum size and would
        // otherwise be clipped to one screenful, hiding later text and every chart).
        run("for (i in 1:150) cat(sprintf('line %03d of the long output\\n', i)); plot(x, x, main='After the long output')", plots: 1)
        let visible = pane.console.enclosingScrollView!.contentSize.height, document = pane.console.frame.height
        precondition(document > visible + 100, "console grows beyond its visible height: document \(document) vs visible \(visible); maxSize \(pane.console.maxSize)")
        let shown = pane.console.enclosingScrollView!.documentVisibleRect
        precondition(shown.maxY >= document - 2, "the console shows its end after a run: visible to \(shown.maxY) of \(document)")
        print("PASS long output grows the console and the view ends at the chart")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = pane.view
        window.orderFront(nil)
        pane.view.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 420, height: 420))
        pane.view.layoutSubtreeIfNeeded()
        pane.console.scrollToEndOfDocument(nil)
        window.orderOut(nil)
        window.contentView = NSView()
        pane.console.scrollToEndOfDocument(nil)
        print("PASS chart output scrolls after attaching, resizing and detaching an inactive tab")
        // Ordinary output is PDF even when svglite is installed. Every page is
        // displayed, with its original file as the caption's single link.
        let sessionFolder = pane.outputFolder!
        let charts = (try FileManager.default.contentsOfDirectory(atPath: sessionFolder.path)).filter { $0.hasPrefix("plots-") }.sorted()
        precondition(charts == ["plots-0001-001.pdf", "plots-0003-001.pdf", "plots-0004-001.pdf", "plots-0004-002.pdf", "plots-0005-001.pdf"], charts.description)
        let originals = try charts.map { name -> (URL, Data, Date) in
            let file = sessionFolder.appendingPathComponent(name)
            return (file, try Data(contentsOf: file), try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!)
        }
        let firstPDF = PDFDocument(url: originals[0].0)!
        precondition(firstPDF.pageCount == 2 && firstPDF.string!.contains("First plot") && firstPDF.string!.contains("Second plot"), "All pages and plot labels survive in the original PDF")
        precondition(firstPDF.page(at: 0)!.bounds(for: .mediaBox).size == NSSize(width: 504, height: 504), "The default chart remains seven inches square")
        precondition(charts.dropFirst().allSatisfy { PDFDocument(url: sessionFolder.appendingPathComponent($0))?.pageCount == 1 }, "Each later device has its own completed PDF")
        var captions = [String]()
        pane.console.textStorage!.enumerateAttribute(.link, in: NSRange(location: 0, length: pane.console.textStorage!.length)) { value, range, _ in
            if let url = value as? URL, url.lastPathComponent.hasPrefix("plots-") { captions.append((pane.console.string as NSString).substring(with: range)) }
        }
        precondition(captions.count == 6 && captions.allSatisfy { $0.hasPrefix("Chart: plots-") && $0.hasSuffix("\n") && $0.contains(".pdf") }, captions.description)
        precondition(captions.prefix(2).elementsEqual(["Chart: plots-0001-001.pdf · page 1\n", "Chart: plots-0001-001.pdf · page 2\n"]), "Multipage PDF captions identify both pages")
        precondition(!pane.console.string.contains("Open plot file") && !pane.console.string.contains("Files written") && !pane.console.string.contains("Plot · "), pane.console.string)
        print("PASS default PDF output preserves all pages, seven-inch geometry, per-device files and page captions without loading svglite")

        // A paired t test's script as the engine writes it from a record: the data as named vectors, the setting, then the body of
        // the recipe in the program's R folder (its comment header, the lines the writer reads, left off).
        let headerKeys = ["# StatsDirect recipe:", "# From the help", "# data:", "# table:", "# matrix:", "# settings:", "# hand-edited:"]
        var recipe = try String(contentsOf: resources.appendingPathComponent("R/recipes/paired-t.R"), encoding: .utf8).components(separatedBy: "\n")
        while let first = recipe.first, first.isEmpty || headerKeys.contains(where: { first.hasPrefix($0) }) { recipe.removeFirst() }
        let script = "# Paired t, from StatsDirect\n# Paired t test with its agreement analysis\n\nbefore <- c(10, 20, 30, 40)   # Before\nafter <- c(8, 17, 25, 32)   # After\nconfidence <- 0.95\n\n" + recipe.joined(separator: "\n")
        run(script, plots: 1)
        precondition(pane.console.string.contains("Paired t-test"))
        run(script, plots: 1)
        run("cat('No new plot\\n')", plots: 0)
        print("PASS generated agreement chart appears inline as PDF, redraw is shown and unchanged plots are not repeated")

        let image = images(pane)[0]
        let bounds = image.attachmentBounds(for: pane.console.textContainer, proposedLineFragment: NSRect(x: 0, y: 0, width: 300, height: 1000), glyphPosition: .zero, characterIndex: 0)
        precondition(bounds.width <= 300 && bounds.width > 0 && bounds.height > 0)
        var links = 0
        let storage = pane.console.textStorage!
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let url = value as? URL, FileManager.default.fileExists(atPath: url.path) { links += 1 }
        }
        precondition(links >= images(pane).count)
        print("PASS plot attachments fit a narrow output column and retain original file links")
        // The files a run writes are listed as links (as the Windows script window lists them), and the Output folder button opens the session folder.
        run("write.csv(data.frame(a = 1:3), 'table.csv', row.names = FALSE)\ncat('written\\n')", plots: 0)
        let folder = pane.outputFolder!
        precondition(FileManager.default.fileExists(atPath: folder.appendingPathComponent("table.csv").path), folder.path)
        var listed = [String]()
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let url = value as? URL, url.lastPathComponent == "table.csv" { listed.append((storage.string as NSString).substring(with: range)) }
        }
        precondition(listed == ["table.csv\n"] && pane.console.string.contains("Files written, to open with a click:"), pane.console.string)
        // a run writing a chart and a file lists the file alone: the chart's caption is its link
        run("write.csv(data.frame(b = 1:2), 'table2.csv', row.names = FALSE); plot(1:3)", plots: 1)
        let lastListing = pane.console.string.components(separatedBy: "Files written, to open with a click:\n").last ?? ""
        precondition(lastListing.hasPrefix("table2.csv\n") && !lastListing.contains("plots-"), lastListing)
        let listings = pane.console.string.components(separatedBy: "Files written").count
        run("cat('nothing written\\n')", plots: 0)
        precondition(pane.console.string.components(separatedBy: "Files written").count == listings, "an unchanged folder lists no files again")
        func buttons(_ view: NSView) -> [NSButton] { view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? buttons($0) } }
        let folderButton = buttons(pane.view).first { $0.title == "Output folder" }
        precondition(folderButton?.isEnabled == true, "Output folder button")
        print("PASS files a run writes are listed as links once, and the Output folder button is offered for the session folder")
        run("svglite::svglite('explicit.svg', width=4, height=3); plot(1:3, main='Explicit SVG'); dev.off(); pdf('explicit.pdf', width=4, height=3); plot(1:3); plot(3:1); dev.off()", plots: 3)
        precondition(try String(contentsOf: folder.appendingPathComponent("explicit.svg"), encoding: .utf8).contains("<svg"), "Explicit R SVG output remains available")
        precondition(PDFDocument(url: folder.appendingPathComponent("explicit.pdf"))?.pageCount == 2, "Explicit PDF device retains both pages")
        run("pdf('explicit-error.pdf'); plot(1:3); stop('Explicit device error')", plots: 1)
        precondition(PDFDocument(url: folder.appendingPathComponent("explicit-error.pdf"))?.pageCount == 1, "An error still flushes the explicit device")
        print("PASS explicit SVG and multipage PDF devices render, including an explicit device flushed after an R error")

        let other = RPane(resources: resources)
        defer { other.shutdown() }
        let beforeConcurrent = images(pane).count
        pane.editor.string = "Sys.sleep(0.5); plot(1:3, main='First session concurrent')"; pane.runScript()
        other.editor.string = "plot(3:1, main='Second session'); plot(1:5, main='Second session page 2')"; other.runScript()
        precondition(pane.isRunning && other.isRunning, "Both R tabs run independently")
        wait([pane, other])
        precondition(images(pane).count == beforeConcurrent + 1 && images(other).count == 2, "Concurrent runs show only their own pages")
        precondition(other.outputFolder != pane.outputFolder, "Concurrent sessions have separate output folders")
        let otherPDF = PDFDocument(url: other.outputFolder!.appendingPathComponent("plots-0001-001.pdf"))!
        precondition(otherPDF.pageCount == 2 && otherPDF.string!.contains("Second session"), "The second session retains its own first device")
        for (file, data, modified) in originals {
            precondition(try Data(contentsOf: file) == data && file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified, "Reruns and other sessions cannot overwrite prior charts")
        }
        print("PASS concurrent R tabs, repeated runs and earlier chart bytes/timestamps remain independent")
        let beforeSplit = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        run("dev.new(onefile=FALSE, width=4, height=3); plot(1:3); plot(3:1); dev.off()", plots: 2)
        let splitFiles = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)).subtracting(beforeSplit).sorted()
        precondition(splitFiles.count == 2 && splitFiles[0].hasSuffix("-001.pdf") && splitFiles[1].hasSuffix("-002.pdf"), "Explicit onefile=FALSE writes independent page files")
        precondition(splitFiles.allSatisfy { name in
            let pdf = PDFDocument(url: folder.appendingPathComponent(name))
            return pdf?.pageCount == 1 && pdf?.page(at: 0)?.bounds(for: .mediaBox).size == NSSize(width: 288, height: 216)
        }, "Explicit page mode and dimensions are preserved")
        print("PASS dev.new can request separate PDF pages and custom dimensions")
        run("dev.new(file='chosen.pdf', width=5, height=4); plot(1:3); dev.off()", plots: 1)
        precondition(PDFDocument(url: folder.appendingPathComponent("chosen.pdf"))?.page(at: 0)?.bounds(for: .mediaBox).size == NSSize(width: 360, height: 288), "dev.new honours an explicitly chosen filename and size")
        let beforeNull = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        run("dev.new(file=NULL); plot(1:3); dev.off()", plots: 0)
        precondition(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == beforeNull, "file=NULL must not create a PDF")
        run("old <- pdf.options(width=6, height=4, onefile=FALSE); plot(1:3); plot(3:1); dev.off(); do.call(pdf.options, old)", plots: 2)
        let optionFiles = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)).subtracting(beforeNull)
        precondition(optionFiles.count == 2 && optionFiles.allSatisfy { PDFDocument(url: folder.appendingPathComponent($0))?.page(at: 0)?.bounds(for: .mediaBox).size == NSSize(width: 432, height: 288) }, "pdf.options controls automatic dimensions and page mode")
        print("PASS dev.new filenames, file=NULL and pdf.options are honoured")
        // Run script while a run is going stops that run and runs the edited script (the Windows script window does the same).
        pane.editor.string = "Sys.sleep(20); cat('slow finished\\n')"; pane.runScript()
        precondition(pane.isRunning, pane.state.stringValue)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        run("cat('edited script ran\\n')", plots: 0)
        precondition(pane.console.string.contains("edited script ran") && !pane.console.string.contains("slow finished") && pane.console.string.contains("Run stopped"), pane.console.string.suffix(400).description)
        print("PASS Run script during a run stops it and runs the edited script")
        precondition(pane.console.textStorage!.containsAttachments)
    }
}
