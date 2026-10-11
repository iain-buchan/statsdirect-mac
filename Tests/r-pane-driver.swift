import Cocoa

@main
struct RPaneChecks {
    @MainActor static func main() throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        _ = NSApplication.shared
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let pane = RPane(resources: resources)
        pane.view.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
        pane.view.layoutSubtreeIfNeeded()
        defer { pane.shutdown() }
        func images() -> [NSTextAttachment] {
            var found = [NSTextAttachment]()
            let storage = pane.console.textStorage!
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                if let attachment = value as? NSTextAttachment { found.append(attachment) }
            }
            return found
        }
        func run(_ script: String, plots: Int) {
            let before = images().count
            pane.editor.string = script; pane.runScript()
            precondition(pane.isRunning, pane.state.stringValue)
            let deadline = Date().addingTimeInterval(30)
            while pane.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            precondition(!pane.isRunning && pane.state.stringValue.contains("Ready"), pane.state.stringValue)
            precondition(images().count == before + plots, "Expected \(plots) new plots.\n" + pane.console.string)
        }
        run("x <- 1:5\nplot(x, x^2, main='First plot')\nplot(x, rev(x), main='Second plot')", plots: 2)
        precondition(images().allSatisfy { ($0.image?.size.width ?? 0) > 0 })
        run("stopifnot(identical(x, 1:5)); cat('Variables retained\\n')", plots: 0)
        run("plot(x, x * 2); stop('Deliberate test error')", plots: 1)
        precondition(pane.console.string.contains("Error: Deliberate test error"))
        run("plot(x); dev.off(); plot(x, -x)", plots: 2)
        print("PASS default plots, multiple pages/devices, errors and variables across runs")

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
        print("PASS generated agreement PDF appears inline, redraw is shown and unchanged plots are not repeated")

        let image = images()[0]
        let bounds = image.attachmentBounds(for: pane.console.textContainer, proposedLineFragment: NSRect(x: 0, y: 0, width: 300, height: 1000), glyphPosition: .zero, characterIndex: 0)
        precondition(bounds.width <= 300 && bounds.width > 0 && bounds.height > 0)
        var links = 0
        let storage = pane.console.textStorage!
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let url = value as? URL, FileManager.default.fileExists(atPath: url.path) { links += 1 }
        }
        precondition(links >= images().count)
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
        let listings = pane.console.string.components(separatedBy: "Files written").count
        run("cat('nothing written\\n')", plots: 0)
        precondition(pane.console.string.components(separatedBy: "Files written").count == listings, "an unchanged folder lists no files again")
        func buttons(_ view: NSView) -> [NSButton] { view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? buttons($0) } }
        let folderButton = buttons(pane.view).first { $0.title == "Output folder" }
        precondition(folderButton?.isEnabled == true, "Output folder button")
        print("PASS files a run writes are listed as links once, and the Output folder button is offered for the session folder")
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
