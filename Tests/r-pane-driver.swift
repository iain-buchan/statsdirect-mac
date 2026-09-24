import Cocoa

@main
struct RPaneChecks {
    @MainActor static func main() throws {
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

        let columns: [[String: Any]] = [
            ["title": "Before", "values": [10, 20, 30, 40]],
            ["title": "After", "values": [8, 17, 25, 32]]
        ]
        let output: [String: Any] = ["history": [
            ["name": "data", "kind": "grid", "value": ["columns": columns]],
            ["name": "gamma", "kind": "confidence", "value": 95],
            ["name": "doAgreement", "kind": "boolean", "value": true]
        ]]
        let plan = try RScriptGenerator.generate(operation: "TPaired", title: "Paired t", output: output, resources: resources)
        run(plan.script, plots: 1)
        precondition(pane.console.string.contains("agreement.pdf"))
        run(plan.script, plots: 1)
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
        precondition(links == images().count)
        print("PASS plot attachments fit a narrow output column and retain original file links")
        precondition(pane.console.textStorage!.containsAttachments)
    }
}
