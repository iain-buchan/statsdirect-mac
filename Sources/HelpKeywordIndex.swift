import Foundation
import CoreFoundation

/// Authored keyword targets supplied by the help builder, independent of the Contents tree.
struct HelpKeywordIndex: Sendable {
    struct Entry: Hashable, Sendable {
        let term: String
        let title: String
        let path: String
    }

    struct Row: Equatable, Sendable {
        let entry: Entry
        let text: String
        let showPath: Bool
    }

    enum IndexError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let message): return message }
        }
    }

    static let unavailableMessage = "This help bundle does not yet include a keyword index."
    private static let english = Locale(identifier: "en_GB")
    let entries: [Entry]
    let rows: [Row]

    /// A missing file is the supported legacy-bundle case. Invalid supplied data is an error.
    static func load(root requestedRoot: URL) throws -> HelpKeywordIndex? {
        let root = requestedRoot.resolvingSymlinksInPath().standardizedFileURL
        let indexFile = root.appendingPathComponent("keyword-index.json")
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: indexFile.path) }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
        catch { throw IndexError.invalid("The help keyword index could not be read.") }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw IndexError.invalid("The help keyword index must be a packaged regular file.")
        }
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: Data(contentsOf: indexFile)) }
        catch { throw IndexError.invalid("The help keyword index contains invalid JSON. Rebuild the desktop help.") }
        guard let object = json as? [String: Any], let version = object["schemaVersion"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              !["d", "f"].contains(String(cString: version.objCType)), version.int64Value == 1,
              let rawEntries = object["entries"] as? [Any] else {
            throw IndexError.invalid("The help keyword index has an unsupported or missing schema. Rebuild the desktop help.")
        }
        let files = try topicFiles(root: root)
        var entries: [Entry] = []
        var seen: [String: Set<String>] = [:]
        for (offset, rawEntry) in rawEntries.enumerated() {
            let number = offset + 1
            let term = try field("term", in: rawEntry, number: number)
            let title = try field("title", in: rawEntry, number: number)
            let path = try target(try field("path", in: rawEntry, number: number), root: root, files: files, number: number)
            let termKey = key(term), pathKey = key(path)
            if seen[termKey, default: []].insert(pathKey).inserted {
                entries.append(Entry(term: term, title: title, path: path))
            }
        }
        entries.sort {
            for pair in [($0.term, $1.term), ($0.title, $1.title)] {
                let order = pair.0.compare(pair.1, options: .caseInsensitive, locale: english)
                if order != .orderedSame { return order == .orderedAscending }
            }
            let left = ordinalPathKey($0.path), right = ordinalPathKey($1.path)
            if left != right { return left.lexicographicallyPrecedes(right) }
            return $0.path.utf16.lexicographicallyPrecedes($1.path.utf16)
        }
        let termCounts = Dictionary(grouping: entries, by: { key($0.term) }).mapValues(\.count)
        let titleCounts = Dictionary(grouping: entries, by: { key($0.term) + "\0" + key($0.title) }).mapValues(\.count)
        let rows = entries.map { entry in
            let showPath = titleCounts[key(entry.term) + "\0" + key(entry.title), default: 0] > 1
            let text = termCounts[key(entry.term), default: 0] > 1
                ? entry.term + " — " + entry.title + (showPath ? " (" + entry.path + ")" : "") : entry.term
            return Row(entry: entry, text: text, showPath: showPath)
        }
        return HelpKeywordIndex(entries: entries, rows: rows)
    }

    func filteredRows(_ text: String) -> [Row] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            [row.entry.term, row.entry.title].contains {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: Self.english) != nil
            }
        }
    }

    private static func key(_ value: String) -> String { value.lowercased(with: english) }

    // Windows uses ordinal case-insensitive ordering for this final path tie-breaker.
    private static func ordinalPathKey(_ value: String) -> [UInt16] {
        var folded = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            let uppercase = String(scalar).uppercased(with: english).unicodeScalars
            folded.append(uppercase.count == 1 ? uppercase.first! : scalar)
        }
        return Array(String(folded).utf16)
    }

    private static func field(_ name: String, in rawEntry: Any, number: Int) throws -> String {
        guard let entry = rawEntry as? [String: Any], let rawText = entry[name] as? String else {
            throw IndexError.invalid("Help keyword index entry \(number) has no valid \(name).")
        }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw IndexError.invalid("Help keyword index entry \(number) has no valid \(name).") }
        return text
    }

    private static func topicFiles(root: URL) throws -> [String: [String]] {
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else {
            throw IndexError.invalid("The packaged help topics could not be read.")
        }
        var files: [String: [String]] = [:]
        while let path = enumerator.nextObject() as? String {
            guard enumerator.fileAttributes?[.type] as? FileAttributeType == .typeRegular else { continue }
            files[key(path), default: []].append(path)
        }
        return files
    }

    private static func target(_ requested: String, root: URL, files: [String: [String]], number: Int) throws -> String {
        func invalid() -> IndexError {
            .invalid("Help keyword index entry \(number) refers to a missing or unsafe topic.")
        }
        let parts = requested.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let decoded = String(parts[0]).removingPercentEncoding, !decoded.isEmpty,
              !decoded.hasPrefix("/"), !decoded.contains("\\"), !decoded.contains(":"), !decoded.contains("?"),
              decoded.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              decoded.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw invalid() }
        let lower = key(decoded)
        guard lower != "index.html", !lower.hasPrefix("resources/"), !lower.hasPrefix("data/"),
              ["htm", "html"].contains((decoded as NSString).pathExtension.lowercased()),
              let matches = files[lower], matches.count == 1, let stored = matches.first else { throw invalid() }
        // Do not follow a linked folder to a topic, even if its destination stays inside the bundle.
        var current = root
        for component in stored.split(separator: "/") {
            current.appendPathComponent(String(component))
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: current.path),
                  attributes[.type] as? FileAttributeType != .typeSymbolicLink else { throw invalid() }
        }
        let actual = current.resolvingSymlinksInPath()
        guard actual.path.hasPrefix(root.path + "/") else { throw invalid() }
        var url = URLComponents()
        url.path = "/" + stored
        if parts.count > 1 {
            guard let fragment = String(parts[1]).removingPercentEncoding,
                  fragment.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw invalid() }
            url.fragment = fragment
        }
        return String(url.percentEncodedPath.dropFirst()) + (url.percentEncodedFragment.map { "#" + $0 } ?? "")
    }
}
