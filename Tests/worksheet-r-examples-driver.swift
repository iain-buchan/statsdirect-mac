import Cocoa

/// The prompt's and script's part of the worksheet R examples (Tests/test_worksheet_r_examples.py):
///   worksheet-r-examples-driver runs.json prompts.json
///
/// Each run carries what the grid's worksheetRImport gave Tests/worksheet-r-examples.mjs: the prompt's preview and, for the
/// data choice the case names, the data. As WorksheetRHost does, this builds the Mac's own prompt from the preview
/// (WorksheetRImportPrompt, built and clicked but never shown, as in Tests/worksheet-r-prompt-driver.swift), makes the
/// case's choices in it as a user would, checks the data against the preview, and writes the script with
/// WorksheetRScript.build. It records what the prompt showed and chose, and the script or the message refusing it.
@main
struct WorksheetRExamplesDriver {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// JSON, handed to the prompt and the script writer as WebKit hands them a script's result: String (NSString),
    /// NSNumber, NSNumber Booleans (CFBoolean), NSNull, arrays and dictionaries. Foundation's JSONSerialization is not
    /// used: it reads text through CFString's UTF-8 decoding, which drops a U+FEFF at the start of a string (as
    /// NSString(bytes:length:encoding:) does), where WebKit's callAsyncJavaScript keeps it.
    enum JSON: Codable {
        case null, bool(Bool), number(Double), string(String), array([JSON]), object([String: JSON])
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Double.self) { self = .number(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([JSON].self) { self = .array(value) }
            else { self = .object(try container.decode([String: JSON].self)) }
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case .bool(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            }
        }
        var foundation: Any {
            switch self {
            case .null: return NSNull()
            case .bool(let value): return NSNumber(value: value)
            case .number(let value): return NSNumber(value: value)
            case .string(let value): return value
            case .array(let value): return value.map(\.foundation)
            case .object(let value): return value.mapValues(\.foundation)
            }
        }
    }

    @MainActor static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        NSApplication.shared.setActivationPolicy(.prohibited)
        do { try run() } catch {
            FileHandle.standardError.write(Data("FAIL \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    @MainActor static func run() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else { throw Failure(message: "Usage: worksheet-r-examples-driver runs.json prompts.json") }
        let input = try JSONDecoder().decode(JSON.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))).foundation
        guard let runs = (input as? [String: Any])?["runs"] as? [[String: Any]] else { throw Failure(message: "The runs could not be read.") }
        var results: [JSON] = []
        for run in runs {
            guard let id = run["id"] as? String, let scope = run["scope"] as? String else { throw Failure(message: "A run has no id or scope.") }
            guard let preview = run["preview"] as? [String: Any], let sheet = preview["sheet"] as? String else {
                results.append(.object(["id": .string(id)]))   // the grid gave no preview; the harness reports why
                continue
            }
            let entire = WorksheetRImportPrompt.Option(preview["entire"] as? [String: Any])
            let selected = WorksheetRImportPrompt.Option(preview["selected"] as? [String: Any])
            let prompt = WorksheetRImportPrompt(external: run["external"] as? Bool == true, sheet: sheet, entire: entire,
                                                selected: selected, selectedReason: preview["selectedReason"] as? String)
            var result: [String: JSON] = [
                "id": .string(id), "title": .string(prompt.alert.messageText), "text": .string(prompt.alert.informativeText),
                "entire": .string(prompt.entireButton.title), "selected": .string(prompt.selectedButton.title),
                "entireEnabled": .bool(prompt.entireButton.isEnabled), "selectedEnabled": .bool(prompt.selectedButton.isEnabled)]
            // The data choice the case names (it stays at No data when that choice is dimmed), then the case's options.
            (scope == "entire" ? prompt.entireButton : prompt.selectedButton).performClick(nil)
            result["headingsSuggested"] = .bool(prompt.headings.state == .on)
            result["headingsEnabled"] = .bool(prompt.headings.isEnabled)
            let options = run["options"] as? [String: Any] ?? [:]
            if options["format"] as? String == "list" {
                prompt.format.selectItem(at: 1)
                prompt.format.sendAction(prompt.format.action, to: prompt.format.target)
            }
            if let headings = options["headings"] as? Bool, prompt.headings.isEnabled, (prompt.headings.state == .on) != headings {
                prompt.headings.performClick(nil)
            }
            if options["friendly"] as? Bool == true, prompt.rFriendlyNames.isEnabled, prompt.rFriendlyNames.state == .off {
                prompt.rFriendlyNames.performClick(nil)
            }
            let choice = prompt.selection
            result["choice"] = .object(["scope": .string(choice.scope.rawValue), "headings": .bool(choice.headings),
                                        "rFriendlyNames": .bool(choice.rFriendlyNames), "asList": .bool(choice.asList)])
            if let data = run["data"] as? [String: Any],
               let expected = choice.scope == .entire ? entire : choice.scope == .selected ? selected : nil {
                // WorksheetRHost's checks before it writes the script: the sheet, range and counts the prompt showed, and
                // one value per data row in every column of a data frame, or only the non-missing ones in a list.
                let dataRows = expected.rowCount - (choice.headings ? 1 : 0)
                let columns = data["columns"] as? [[String: Any]]
                if data["sheet"] as? String != sheet || data["range"] as? String != expected.range
                    || WorksheetRScript.integer(data["rowCount"]) != expected.rowCount
                    || WorksheetRScript.integer(data["columnCount"]) != expected.columnCount {
                    result["hostError"] = .string("The worksheet changed. Open the R import prompt again.")
                } else if columns?.count != expected.columnCount
                            || columns.map({ WorksheetRScript.holdsDataRows($0, dataRows: dataRows, asList: choice.asList) }) != true {
                    result["hostError"] = .string("The worksheet data could not be read.")
                } else {
                    do { result["script"] = .string(try WorksheetRScript.build(data, rFriendlyNames: choice.rFriendlyNames, asList: choice.asList)) }
                    catch let failure as ConversationRScript.Failure { result["scriptError"] = .string(failure.message) }
                }
            }
            results.append(.object(result))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(JSON.object(["results": .array(results)])).write(to: URL(fileURLWithPath: arguments[2]))
        print("prompt and script: \(results.count) runs through WorksheetRImportPrompt and WorksheetRScript")
    }
}
