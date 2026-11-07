import Foundation
import CoreFoundation

/// Authored keyword targets supplied by the help builder, independent of the Contents tree. Reading, validation, order
/// and filtering follow the Windows help catalogue and picker (HelpCatalog.cs and HelpIndexMenu.cs at Windows d783a494)
/// as .NET 10 runs them on ICU: the same en-GB collation and search, ordinal case-insensitive keys, System.Uri's forms
/// of a path and fragment, and File.ReadAllText's decoding.
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

    /// Data/Alias.xml's help names and IDs in document order, each Map giving its Name and then its ResolvedId, as
    /// HelpCatalog's constructor reads them. A later mapping of the same key, compared without regard to case, wins.
    struct Aliases: ExpressibleByDictionaryLiteral, Sendable {
        let maps: [(key: String, link: String)]
        init(_ maps: [(key: String, link: String)]) { self.maps = maps }
        init(dictionaryLiteral elements: (String, String)...) { maps = elements.map { (key: $0.0, link: $0.1) } }
    }

    static let unavailableMessage = "This help bundle does not yet include a keyword index."
    private static let english = Locale(identifier: "en_GB")
    let entries: [Entry]
    let rows: [Row]
    private let searchText: [SearchText]
    private struct SearchText: Sendable { let term: [UInt16]; let title: [UInt16] }
    private struct InvalidTopicPath: Error {}

    private init(entries: [Entry], rows: [Row]) {
        self.entries = entries
        self.rows = rows
        searchText = rows.map { SearchText(term: Array($0.entry.term.utf16), title: Array($0.entry.title.utf16)) }
    }

    /// Windows's File.Exists: an index file is present, while a folder of that name counts as no index.
    static func exists(root requestedRoot: URL) -> Bool {
        let file = requestedRoot.resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent("keyword-index.json")
        guard let type = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.type] as? FileAttributeType else { return false }
        return type != .typeDirectory
    }

    /// A missing file is the supported legacy-bundle case. Invalid supplied data is an error naming the index, never a
    /// partial list. `aliases` are the help IDs and names of Data/Alias.xml, which Windows also accepts as targets.
    static func load(root requestedRoot: URL, aliases: Aliases = [:]) throws -> HelpKeywordIndex? {
        let root = requestedRoot.resolvingSymlinksInPath().standardizedFileURL
        guard exists(root: root) else { return nil }
        let indexFile = root.appendingPathComponent("keyword-index.json")
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: indexFile.path) }
        catch { throw IndexError.invalid("The help keyword index could not be read.") }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw IndexError.invalid("The help keyword index must be a packaged regular file.")
        }
        guard let data = try? Data(contentsOf: indexFile) else { throw IndexError.invalid("The help keyword index could not be read.") }
        let document: JSONValue
        do { var parser = StrictJSON(text(of: data)); document = try parser.document() }
        catch { throw IndexError.invalid("The help keyword index contains invalid JSON. Rebuild the desktop help.") }
        guard case .number("1")? = document.member("schemaVersion"), case .array(let rawEntries)? = document.member("entries") else {
            throw IndexError.invalid("The help keyword index has an unsupported or missing schema. Rebuild the desktop help.")
        }
        let files = try topicFiles(root: root)
        var lookup: [[UInt16]: String] = [:]
        for map in aliases.maps where !DotNetText.isBlank(map.key) { lookup[OrdinalCase.key(map.key)] = map.link }
        var entries: [Entry] = []
        var seen: [[UInt16]: Set<[UInt16]>] = [:]
        for (offset, rawEntry) in rawEntries.enumerated() {
            let number = offset + 1
            let term = try field("term", in: rawEntry, number: number)
            let title = try field("title", in: rawEntry, number: number)
            let target = try field("path", in: rawEntry, number: number)
            let units = Array(target.utf16)
            if DotNetUri.absolute(target) != nil || units.starts(with: [0x2F, 0x2F]) || units.contains(0x5C) || units.contains(0) {
                throw IndexError.invalid("Help keyword index entry \(number) does not name a packaged topic.")
            }
            let resolved: (path: String, fragment: String)?
            do { resolved = try resolve(target, aliases: lookup, root: root, files: files) }
            catch { throw IndexError.invalid("Help keyword index entry \(number) has an invalid topic path.") }
            guard let page = resolved, !OrdinalCase.equal(page.path, "index.html"),
                  !OrdinalCase.hasPrefix(page.path, "resources/"), !OrdinalCase.hasPrefix(page.path, "Data/") else {
                throw IndexError.invalid("Help keyword index entry \(number) refers to a missing or unsafe topic.")
            }
            let path = page.path + page.fragment
            if seen[OrdinalCase.key(term), default: []].insert(OrdinalCase.key(path)).inserted {
                entries.append(Entry(term: term, title: title, path: path))
            }
        }
        // OrderBy term, ThenBy title with the en-GB comparer ignoring case, ThenBy path ordinally ignoring case. LINQ's
        // sort is stable, so entries that tie throughout keep their authored order.
        let keys = entries.map { (term: Array($0.term.utf16), title: Array($0.title.utf16), path: Array($0.path.utf16)) }
        let sorted = entries.indices.sorted { left, right in
            let a = keys[left], b = keys[right]
            var order = cultureCompare(a.term, b.term)
            if order == 0 { order = cultureCompare(a.title, b.title) }
            if order == 0 { order = OrdinalCase.compare(a.path, b.path) }
            return order != 0 ? order < 0 : left < right
        }.map { entries[$0] }
        // HelpIndexMenu.Prepare: a term listed more than once shows its titles, and a title repeated under one term its path.
        let termKeys = sorted.map { OrdinalCase.key($0.term) }
        let titleKeys = sorted.map { OrdinalCase.key($0.term + "\u{0}" + $0.title) }
        let termCounts = Dictionary(termKeys.map { ($0, 1) }, uniquingKeysWith: +)
        let titleCounts = Dictionary(titleKeys.map { ($0, 1) }, uniquingKeysWith: +)
        let rows = sorted.indices.map { index in
            let entry = sorted[index]
            let showPath = titleCounts[titleKeys[index], default: 0] > 1
            let text = termCounts[termKeys[index], default: 0] > 1
                ? entry.term + " — " + entry.title + (showPath ? " (" + entry.path + ")" : "") : entry.term
            return Row(entry: entry, text: text, showPath: showPath)
        }
        return HelpKeywordIndex(entries: sorted, rows: rows)
    }

    /// The filter text as Windows's String.Trim leaves it, without leading or trailing Unicode white space. The picker
    /// counts a filter that trims to nothing as no filter.
    static func trimmedQuery(_ text: String) -> String { DotNetText.trimmed(text) }

    /// HelpIndexMenu.ApplyFilter: CompareInfo.IndexOf in the en-GB culture, ignoring case and non-spacing marks, on the
    /// term or the title. That is ICU's string search at primary strength, which also equates compatibility forms such as
    /// I² and I2, typographic and straight apostrophes, and æ and ae, but keeps full-width letters apart.
    func filteredRows(_ text: String) -> [Row] {
        let query = Array(Self.trimmedQuery(text).utf16)
        guard !query.isEmpty else { return rows }
        if let collation = KeywordCollation.shared, let found = collation.search(query, { contains in
            zip(rows, searchText).filter { contains($0.1.term) || contains($0.1.title) }.map(\.0)
        }) { return found }
        // Without the system's ICU library, Foundation's case- and accent-blind search stands in.
        let pattern = String(decoding: query, as: UTF16.self)
        return rows.filter { row in
            [row.entry.term, row.entry.title].contains { $0.range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive], locale: Self.english) != nil }
        }
    }

    private static func cultureCompare(_ left: [UInt16], _ right: [UInt16]) -> Int {
        if let collation = KeywordCollation.shared { return collation.compare(left, right) }
        let order = String(decoding: left, as: UTF16.self).compare(String(decoding: right, as: UTF16.self), options: .caseInsensitive, locale: english)
        return order == .orderedAscending ? -1 : order == .orderedDescending ? 1 : 0
    }

    /// File.ReadAllText: a byte-order mark selects UTF-16, UTF-32 or UTF-8, anything else is UTF-8, and each malformed
    /// sequence becomes U+FFFD. Only the first mark is removed, so a second one remains in the text.
    private static func text(of data: Data) -> [UInt16] {
        let bytes = [UInt8](data)
        func utf16(_ body: ArraySlice<UInt8>, bigEndian: Bool) -> [UInt16] {
            var units: [UInt16] = []
            units.reserveCapacity(body.count / 2 + 1)
            var index = body.startIndex
            while index + 1 < body.endIndex {
                let first = UInt16(body[index]), second = UInt16(body[index + 1])
                units.append(bigEndian ? first << 8 | second : second << 8 | first)
                index += 2
            }
            var text = Array(String(decoding: units, as: UTF16.self).utf16)
            if index < body.endIndex { text.append(0xFFFD) }
            return text
        }
        func utf32(_ body: ArraySlice<UInt8>, bigEndian: Bool) -> [UInt16] {
            var text = String.UnicodeScalarView()
            var index = body.startIndex
            while index + 3 < body.endIndex {
                let quad = (0..<4).map { UInt32(body[index + $0]) }
                let value = bigEndian ? quad[0] << 24 | quad[1] << 16 | quad[2] << 8 | quad[3] : quad[3] << 24 | quad[2] << 16 | quad[1] << 8 | quad[0]
                text.append(Unicode.Scalar(value) ?? "\u{FFFD}")
                index += 4
            }
            if index < body.endIndex { text.append("\u{FFFD}") }
            return Array(String(text).utf16)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return bytes.count >= 4 && bytes[2] == 0 && bytes[3] == 0 ? utf32(bytes[4...], bigEndian: false) : utf16(bytes[2...], bigEndian: false)
        }
        if bytes.starts(with: [0xFE, 0xFF]) { return utf16(bytes[2...], bigEndian: true) }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return Array(String(decoding: bytes[3...], as: UTF8.self).utf16) }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return utf32(bytes[4...], bigEndian: true) }
        return Array(String(decoding: bytes, as: UTF8.self).utf16)
    }

    /// HelpCatalog.ReadIndexString: a non-blank string, trimmed; text with an unpaired surrogate is refused.
    private static func field(_ name: String, in rawEntry: JSONValue, number: Int) throws -> String {
        guard case .string(let units)? = rawEntry.member(name) else {
            throw IndexError.invalid("Help keyword index entry \(number) has no valid \(name).")
        }
        var index = 0
        while index < units.count {
            switch units[index] {
            case 0xD800...0xDBFF:
                guard index + 1 < units.count, (0xDC00...0xDFFF).contains(units[index + 1]) else {
                    throw IndexError.invalid("Help keyword index entry \(number) has invalid \(name) text.")
                }
                index += 2
            case 0xDC00...0xDFFF: throw IndexError.invalid("Help keyword index entry \(number) has invalid \(name) text.")
            default: index += 1
            }
        }
        let text = String(decoding: units, as: UTF16.self)
        guard !DotNetText.isBlank(text) else { throw IndexError.invalid("Help keyword index entry \(number) has no valid \(name).") }
        return DotNetText.trimmed(text)
    }

    /// The packaged regular files, keyed as Windows's file system compares names: ordinally, ignoring case.
    private static func topicFiles(root: URL) throws -> [[UInt16]: [String]] {
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else {
            throw IndexError.invalid("The packaged help topics could not be read.")
        }
        var files: [[UInt16]: [String]] = [:]
        while let path = enumerator.nextObject() as? String {
            guard enumerator.fileAttributes?[.type] as? FileAttributeType == .typeRegular else { continue }
            files[OrdinalCase.key(path), default: []].append(path)
        }
        return files
    }

    /// HelpCatalog.Resolve for a keyword target. An alias, or a packaged .htm or .html page named in the text's own case,
    /// with any leading slashes and a Content/ prefix, and any query dropped; an alias may also give the page's address on
    /// the StatsDirect web site, the help's GitHub pages or the Windows help origin. Traversal, helper folders, missing
    /// pages and names Windows cannot hold are refused, and so, on the Mac, are a page reached through a linked file or
    /// folder and a name that matches more than one file when case is ignored. The result is the path and the fragment,
    /// with its '#', in the forms System.Uri gives them. An embedded NUL is the one invalid path that throws.
    private static func resolve(_ requested: String, aliases: [[UInt16]: String], root: URL, files: [[UInt16]: [String]]) throws -> (path: String, fragment: String)? {
        var topic = DotNetText.isBlank(requested) || requested == "0" ? "1000" : requested
        if let mapped = aliases[OrdinalCase.key(topic)] { topic = mapped }
        if let address = DotNetUri.absolute(topic) {
            if address.host == "www.statsdirect.com" || address.host == "statsdirect.com" {
                guard OrdinalCase.hasPrefix(address.path, "/help/") else { return nil }
                topic = String(decoding: Array(address.path.utf16).dropFirst(6), as: UTF16.self) + address.fragment
            } else if address.host == "iain-buchan.github.io", OrdinalCase.hasPrefix(address.path, "/statisticalhelp/") {
                topic = String(decoding: Array(address.path.utf16).dropFirst(17), as: UTF16.self) + address.fragment
            } else if address.authority == "https://help.statsdirect.invalid" {
                topic = address.pathAndQuery + address.fragment
            } else { return nil }
        }
        let units = Array(topic.utf16)
        var path = Array(DotNetUri.unescapeDataString(Array(units.prefix { $0 != 0x23 && $0 != 0x3F })).drop { $0 == 0x2F })
        if OrdinalCase.hasPrefix(path, Array("Content/".utf16)) { path.removeFirst(8) }
        let segments = path.split(separator: 0x2F, omittingEmptySubsequences: false)
        if path.contains(0x5C) || path.contains(0x3A) || segments.contains(where: { $0.elementsEqual([0x2E]) || $0.elementsEqual([0x2E, 0x2E]) }) { return nil }
        // Path.GetFullPath refuses an embedded NUL, which LoadIndexEntries reports as an invalid topic path.
        if path.contains(0) { throw InvalidTopicPath() }
        // Path.Combine keeps a rooted path whole, and that lies outside the help folder.
        if path.first == 0x2F { return nil }
        // File.Exists finds no file whose name Windows cannot hold.
        if path.contains(where: { $0 < 0x20 || [0x22, 0x2A, 0x3C, 0x3E, 0x3F, 0x7C].contains($0) }) { return nil }
        let name = Array(segments.last ?? [])
        guard let dot = name.lastIndex(of: 0x2E), [Array(".htm".utf16), Array(".html".utf16)].contains(Array(name[dot...])) else { return nil }
        // Path.GetFullPath joins repeated separators, so the page is looked up without empty segments.
        let packaged = Array(segments.filter { !$0.isEmpty }.joined(separator: [0x2F]))
        guard let matches = files[OrdinalCase.key(packaged)], matches.count == 1, let stored = matches.first else { return nil }
        var current = root
        for component in stored.split(separator: "/") {
            current.appendPathComponent(String(component))
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: current.path),
                  attributes[.type] as? FileAttributeType != .typeSymbolicLink else { return nil }
        }
        guard current.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else { return nil }
        let fragment = units.firstIndex(of: 0x23).map { Array(units[$0...]) } ?? []
        let address = DotNetUri.canonical(path + fragment)
        return (address.path, address.fragment)
    }
}

/// .NET's white space: char.IsWhiteSpace is Unicode's White_Space property, which, unlike Foundation's
/// whitespacesAndNewlines, leaves out U+200B ZERO WIDTH SPACE.
private enum DotNetText {
    static func trimmed(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
              let last = scalars.lastIndex(where: { !$0.properties.isWhitespace }) else { return "" }
        return String(scalars[first...last])
    }
    static func isBlank(_ text: String) -> Bool { text.unicodeScalars.allSatisfy { $0.properties.isWhitespace } }
}

/// StringComparison.OrdinalIgnoreCase as .NET applies it on ICU: each UTF-16 unit takes its simple upper-case mapping,
/// except that ı and ſ keep their own, and a surrogate pair takes its scalar's. Equal keys are equal strings.
private enum OrdinalCase {
    static func upper(_ scalar: UInt32) -> UInt32 {
        if scalar == 0x131 || scalar == 0x17F { return scalar }
        if let collation = KeywordCollation.shared { return collation.upper(scalar) }
        guard let value = Unicode.Scalar(scalar) else { return scalar }
        let mapped = value.properties.uppercaseMapping.unicodeScalars
        return mapped.count == 1 ? mapped.first!.value : scalar
    }
    private static func isPair(_ units: [UInt16], _ index: Int) -> Bool {
        UTF16.isLeadSurrogate(units[index]) && index + 1 < units.count && UTF16.isTrailSurrogate(units[index + 1])
    }
    private static func scalar(_ units: [UInt16], _ index: Int) -> UInt32 {
        0x10000 + (UInt32(units[index]) - 0xD800) << 10 + (UInt32(units[index + 1]) - 0xDC00)
    }
    private static func upperUnit(_ unit: UInt16) -> UInt16 {
        UTF16.isLeadSurrogate(unit) || UTF16.isTrailSurrogate(unit) ? unit : UInt16(truncatingIfNeeded: upper(UInt32(unit)))
    }
    static func key(_ text: String) -> [UInt16] { key(Array(text.utf16)) }
    static func key(_ units: [UInt16]) -> [UInt16] {
        var result: [UInt16] = []
        result.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            if isPair(units, index) {
                result.append(contentsOf: (Unicode.Scalar(upper(scalar(units, index))) ?? "\u{FFFD}").utf16)
                index += 2
            } else {
                result.append(upperUnit(units[index]))
                index += 1
            }
        }
        return result
    }
    /// Ordinal.CompareStringIgnoreCase (OrdinalCasing.CompareStringIgnoreCase at .NET 10).
    static func compare(_ a: [UInt16], _ b: [UInt16]) -> Int {
        var index = 0
        while index < min(a.count, b.count) {
            let pairA = isPair(a, index), pairB = isPair(b, index)
            if !pairA {
                if pairB { return -1 }
                if a[index] == b[index] { index += 1; continue }
                let upperA = Int(upperUnit(a[index])), upperB = Int(upperUnit(b[index]))
                if upperA == upperB { index += 1; continue }
                return upperA - upperB
            }
            if !pairB { return 1 }
            if a[index] == b[index] && a[index + 1] == b[index + 1] { index += 2; continue }
            let upperA = Int(upper(scalar(a, index))), upperB = Int(upper(scalar(b, index)))
            if upperA == upperB { index += 2; continue }
            return upperA - upperB
        }
        return a.count - b.count
    }
    static func equal(_ text: String, _ other: String) -> Bool { key(text) == key(other) }
    static func hasPrefix(_ text: String, _ prefix: String) -> Bool { hasPrefix(Array(text.utf16), Array(prefix.utf16)) }
    static func hasPrefix(_ text: [UInt16], _ prefix: [UInt16]) -> Bool { key(text).starts(with: key(prefix)) }
}

/// The parts of System.Uri that HelpCatalog relies on, measured against .NET 10: whether text is an absolute address,
/// what Uri.UnescapeDataString makes of a path, and the forms Uri.AbsolutePath and Uri.Fragment give.
private enum DotNetUri {
    struct Address {
        let host: String
        let path: String
        let fragment: String
        let pathAndQuery: String
        /// Uri.GetLeftPart(UriPartial.Authority).
        let authority: String
    }

    private static let authoritySchemes: Set<String> = ["http", "https", "ftp", "gopher", "nntp", "telnet", "ldap", "ws", "wss", "net.tcp", "net.pipe"]
    private static let defaultPorts: [String: String] = ["http": "80", "https": "443", "ftp": "21", "gopher": "70", "nntp": "119", "telnet": "23", "ldap": "389", "ws": "80", "wss": "443"]

    private static func isHex(_ unit: UInt16) -> Bool { (0x30...0x39).contains(unit) || (0x41...0x46).contains(unit) || (0x61...0x66).contains(unit) }
    private static func hex(_ unit: UInt16) -> UInt8 { UInt8(unit <= 0x39 ? unit - 0x30 : (unit | 0x20) - 0x57) }
    private static func isLetter(_ unit: UInt16) -> Bool { (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit) }
    private static func isDigit(_ unit: UInt16) -> Bool { (0x30...0x39).contains(unit) }
    private static func escapeAt(_ units: [UInt16], _ index: Int) -> UInt8? {
        index + 2 < units.count && units[index] == 0x25 && isHex(units[index + 1]) && isHex(units[index + 2])
            ? hex(units[index + 1]) << 4 | hex(units[index + 2]) : nil
    }

    /// A well-formed UTF-8 sequence spelt as consecutive escapes from `index`: its scalar and how many escapes it took.
    private static func utf8Escapes(_ units: [UInt16], _ index: Int) -> (scalar: UInt32, count: Int)? {
        guard let lead = escapeAt(units, index) else { return nil }
        let count: Int, second: ClosedRange<UInt8>, initial: UInt32
        switch lead {
        case 0xC2...0xDF: count = 2; second = 0x80...0xBF; initial = UInt32(lead & 0x1F)
        case 0xE0: count = 3; second = 0xA0...0xBF; initial = UInt32(lead & 0x0F)
        case 0xE1...0xEC, 0xEE...0xEF: count = 3; second = 0x80...0xBF; initial = UInt32(lead & 0x0F)
        case 0xED: count = 3; second = 0x80...0x9F; initial = UInt32(lead & 0x0F)
        case 0xF0: count = 4; second = 0x90...0xBF; initial = UInt32(lead & 0x07)
        case 0xF1...0xF3: count = 4; second = 0x80...0xBF; initial = UInt32(lead & 0x07)
        case 0xF4: count = 4; second = 0x80...0x8F; initial = UInt32(lead & 0x07)
        default: return nil
        }
        var scalar = initial
        for position in 1..<count {
            guard let byte = escapeAt(units, index + 3 * position), (position == 1 ? second : 0x80...0xBF).contains(byte) else { return nil }
            scalar = scalar << 6 | UInt32(byte & 0x3F)
        }
        return (scalar, count)
    }

    /// RFC 3987's ucschar, the characters that Uri decodes from escapes in a path or fragment and escapes again.
    private static func isIRICharacter(_ scalar: UInt32) -> Bool {
        switch scalar {
        case 0xA0...0xD7FF, 0xF900...0xFDCF, 0xFDF0...0xFFEF: return true
        case 0x10000...0xDFFFF: return scalar & 0xFFFF < 0xFFFE
        case 0xE1000...0xEFFFD: return true
        default: return false
        }
    }

    private static func appendEscapes(of scalar: Unicode.Scalar, to text: inout String) {
        for byte in String(scalar).utf8 { text += String(format: "%%%02X", byte) }
    }

    /// Uri.UnescapeDataString: escapes of ASCII and of well-formed UTF-8 become characters; anything else stays as written.
    static func unescapeDataString(_ units: [UInt16]) -> [UInt16] {
        var result: [UInt16] = []
        var index = 0
        while index < units.count {
            if let byte = escapeAt(units, index) {
                if byte < 0x80 { result.append(UInt16(byte)); index += 3; continue }
                if let decoded = utf8Escapes(units, index), let scalar = Unicode.Scalar(decoded.scalar) {
                    result.append(contentsOf: scalar.utf16); index += 3 * decoded.count; continue
                }
                result.append(contentsOf: units[index...index + 2]); index += 3; continue
            }
            result.append(units[index]); index += 1
        }
        return result
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        isLetter(UInt16(byte)) || isDigit(UInt16(byte)) || [0x2D, 0x2E, 0x5F, 0x7E].contains(byte)
    }

    /// Whether Uri rewrites the escapes of an address: it does once anything in it needs decoding beyond ASCII, that is,
    /// a non-ASCII character, an escape of an unreserved or non-ASCII byte, or a '%' with two characters after it that
    /// start no escape.
    private static func rewritesEscapes(_ units: [UInt16]) -> Bool {
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit > 0x7F { return true }
            if unit == 0x25 {
                if let byte = escapeAt(units, index) {
                    if byte >= 0x80 || isUnreserved(byte) { return true }
                    index += 3
                    continue
                }
                if index + 2 < units.count { return true }
            }
            index += 1
        }
        return false
    }

    /// Uri's first pass over a component when it rewrites an address's escapes: it decodes the escapes of unreserved
    /// ASCII, of the space and " < > ^ ` { | }, and of well-formed UTF-8 for IRI characters, and keeps the rest as
    /// written. A '%' that starts no escape takes the two characters after it with it, so an escape among them is never
    /// decoded, and a surrogate pair it splits becomes U+FFFD. Also whether the pass changed anything.
    private static func decoded(_ units: [UInt16], rewrite: Bool) -> (units: [UInt16], changed: Bool) {
        guard rewrite else { return (units, false) }
        var result: [UInt16] = []
        result.reserveCapacity(units.count)
        var changed = false
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit >= 0x80 {
                // Uri escapes here a character that may not stand in an IRI, which counts as a change.
                if UTF16.isLeadSurrogate(unit), index + 1 < units.count, UTF16.isTrailSurrogate(units[index + 1]) {
                    if !isIRICharacter(0x10000 + (UInt32(unit) - 0xD800) << 10 + (UInt32(units[index + 1]) - 0xDC00)) { changed = true }
                    result.append(contentsOf: [unit, units[index + 1]]); index += 2; continue
                }
                if !isIRICharacter(UInt32(unit)) { changed = true }
                result.append(unit); index += 1; continue
            }
            guard unit == 0x25 else { result.append(unit); index += 1; continue }
            if let byte = escapeAt(units, index) {
                if byte < 0x80, isUnreserved(byte) || [0x20, 0x22, 0x3C, 0x3E, 0x5E, 0x60, 0x7B, 0x7C, 0x7D].contains(byte) {
                    result.append(UInt16(byte)); changed = true; index += 3
                } else if byte >= 0x80, let sequence = utf8Escapes(units, index), isIRICharacter(sequence.scalar), let scalar = Unicode.Scalar(sequence.scalar) {
                    result.append(contentsOf: scalar.utf16); changed = true; index += 3 * sequence.count
                } else {
                    result.append(contentsOf: units[index...index + 2]); index += 3
                }
                continue
            }
            result.append(0x25)
            let limit = min(index + 3, units.count)
            var next = index + 1
            while next < limit {
                let unit = units[next]
                if UTF16.isLeadSurrogate(unit), next + 1 < limit, UTF16.isTrailSurrogate(units[next + 1]) {
                    result.append(contentsOf: [unit, units[next + 1]]); next += 2
                } else if UTF16.isLeadSurrogate(unit) || UTF16.isTrailSurrogate(unit) {
                    result.append(0xFFFD); changed = true; next += 1
                } else {
                    result.append(unit); next += 1
                }
            }
            index = limit
        }
        return (result, changed)
    }

    /// Uri's escaping of a component: what a URI cannot hold is escaped in capitals, a '%' that starts an escape stays,
    /// and in a path a backslash is a slash.
    private static func escaped(_ units: [UInt16], fragment: Bool) -> String {
        var text = ""
        var index = 0
        while index < units.count {
            let unit = units[index]
            switch unit {
            case 0x25: text += escapeAt(units, index) != nil ? "%" : "%25"
            case 0x5C: text += fragment ? "%5C" : "/"
            case 0x23, 0x3F:
                // A fragment or query holds '#' and '?' as they are; a path never does, as they end it.
                text += fragment ? String(UnicodeScalar(UInt8(unit))) : String(format: "%%%02X", unit)
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x2E, 0x5F, 0x7E, 0x21, 0x24, 0x26...0x2C, 0x2F, 0x3A, 0x3B, 0x3D, 0x40, 0x5B, 0x5D:
                text.unicodeScalars.append(UnicodeScalar(UInt8(unit)))
            case 0..<0x80: text += String(format: "%%%02X", unit)
            case 0xD800...0xDBFF where index + 1 < units.count && UTF16.isTrailSurrogate(units[index + 1]):
                appendEscapes(of: Unicode.Scalar(0x10000 + (UInt32(unit) - 0xD800) << 10 + (UInt32(units[index + 1]) - 0xDC00))!, to: &text)
                index += 1
            case 0xD800...0xDFFF: appendEscapes(of: "\u{FFFD}", to: &text)
            default: appendEscapes(of: Unicode.Scalar(unit)!, to: &text)
            }
            index += 1
        }
        return text
    }

    /// The path, query and fragment of an address's text after its origin, as Uri.AbsolutePath, the query of
    /// Uri.PathAndQuery and Uri.Fragment give them. Uri trims spaces, tabs and line breaks from the end of an address once
    /// decoded, but leaves them on a path that ends the address if its first pass changed that path.
    private static func parts(_ units: [UInt16], compress: Bool = true) -> (path: String, query: String, fragment: String) {
        let rewrite = rewritesEscapes(units)
        func trimmed(_ part: [UInt16]) -> [UInt16] {
            var part = part
            while let last = part.last, [0x20, 0x09, 0x0A, 0x0D].contains(last) { part.removeLast() }
            return part
        }
        let hash = units.firstIndex(of: 0x23)
        let beforeHash = hash.map { Array(units[..<$0]) } ?? units
        let query = beforeHash.firstIndex(of: 0x3F)
        var path = decoded(query.map { Array(beforeHash[..<$0]) } ?? beforeHash, rewrite: rewrite)
        if hash == nil, query == nil, !path.changed { path.units = trimmed(path.units) }
        let queryText = query.map { "?" + escaped(decoded(Array(beforeHash[($0 + 1)...]), rewrite: rewrite).units, fragment: true) } ?? ""
        let fragment = hash.map { "#" + escaped(trimmed(decoded(Array(units[($0 + 1)...]), rewrite: rewrite).units), fragment: true) } ?? ""
        let written = escaped(path.units, fragment: false)
        let absolutePath = written.hasPrefix("/") ? written : "/" + written
        return (compress ? removingDotSegments(absolutePath) : absolutePath, queryText, fragment)
    }

    /// RFC 3986's remove_dot_segments, which Uri applies to the path of a hierarchical address.
    private static func removingDotSegments(_ path: String) -> String {
        var segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        var output: [Substring] = []
        while let segment = segments.popFirst() {
            if segment == "." || segment == ".." {
                if segment == "..", !output.isEmpty { output.removeLast() }
                if segments.isEmpty { output.append("") }
            } else {
                output.append(segment)
            }
        }
        return "/" + output.joined(separator: "/")
    }

    /// AbsolutePath, without its leading slashes, and Fragment of Uri("https://help.statsdirect.invalid/" + text).
    static func canonical(_ units: [UInt16]) -> (path: String, fragment: String) {
        let address = parts(units)
        return (String(address.path.drop { $0 == "/" }), address.fragment)
    }

    /// Uri.TryCreate(text, UriKind.Absolute) as it answers on Windows, and for an address the parts HelpCatalog.Resolve
    /// reads. A drive path such as C:/x and a UNC path are absolute file addresses there; a single leading '/' is not.
    static func absolute(_ raw: String) -> Address? {
        var units = Array(raw.utf16)
        while let first = units.first, [0x20, 0x09, 0x0A, 0x0D].contains(first) { units.removeFirst() }
        let end = units.lastIndex { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }.map { $0 + 1 } ?? 0
        guard let first = units.first, end > 0 else { return nil }
        // Scheme and authority are read from the address without its trailing white space.
        let address = Array(units[..<end])
        let none = Address(host: "", path: "", fragment: "", pathAndQuery: "", authority: "")
        func isSlash(_ index: Int) -> Bool { index < address.count && (address[index] == 0x2F || address[index] == 0x5C) }
        // A drive letter followed by a separator, or a UNC share, whose server follows any number of separators.
        if isLetter(first), address.count >= 3, address[1] == 0x3A, isSlash(2) { return none }
        if isSlash(0) && isSlash(1) {
            var start = 2
            while isSlash(start) { start += 1 }
            return authorityAddress(scheme: "file", units, from: start)
        }
        guard isLetter(first), let colon = address.firstIndex(of: 0x3A),
              address[1..<colon].allSatisfy({ isLetter($0) || isDigit($0) || [0x2B, 0x2D, 0x2E].contains($0) }) else { return nil }
        guard colon >= 2 else { return nil }
        let scheme = String(decoding: address[..<colon], as: UTF16.self).lowercased()
        let rest = colon + 1
        let slashes = isSlash(rest) && isSlash(rest + 1)
        if scheme == "file" {
            if slashes {
                // file:/// has an empty server and file://// and beyond name a UNC server.
                var start = rest + 2
                if isSlash(start) && isSlash(start + 1) { while isSlash(start) { start += 1 } }
                return authorityAddress(scheme: scheme, units, from: start)
            }
            if rest + 2 < address.count, isLetter(address[rest]), address[rest + 1] == 0x3A, isSlash(rest + 2) { return none }
            return nil
        }
        if authoritySchemes.contains(scheme) {
            guard slashes else { return nil }
            return authorityAddress(scheme: scheme, units, from: rest + 2)
        }
        return slashes ? authorityAddress(scheme: scheme, units, from: rest + 2) : none
    }

    /// The server part of an address and what follows it. Uri accepts a server named by letters, digits, '-', '_', '.' and
    /// characters beyond ASCII, not starting with '.', an IPv4 or bracketed IPv6 address, an optional user and an optional
    /// port of at most 65535; schemes that name a host need one.
    /// An IPv6 literal as Uri accepts one between brackets: RFC 4291's forms of one to four hex digits a group, with one
    /// '::' at most and an IPv4 address in decimal, without leading zeros, as the last two groups, and any zone after '%'.
    /// (Uri also takes a final IPv4 octet such as 04, which this does not.)
    private static func isIPv6(_ literal: [UInt16]) -> Bool {
        let address = literal.prefix { $0 != 0x25 }
        guard !address.isEmpty else { return false }
        var halves: [ArraySlice<UInt16>] = []
        var rest = address[...]
        while let colon = rest.indices.first(where: { rest[$0] == 0x3A && $0 + 1 < rest.endIndex && rest[$0 + 1] == 0x3A }) {
            halves.append(rest[..<colon]); rest = rest[(colon + 2)...]
        }
        halves.append(rest)
        guard halves.count <= 2 else { return false }
        var groups = 0
        for (side, half) in halves.enumerated() where !half.isEmpty {
            let parts = half.split(separator: 0x3A, omittingEmptySubsequences: false)
            for (position, part) in parts.enumerated() {
                if side == halves.count - 1, position == parts.count - 1, part.contains(0x2E) {
                    let octets = part.split(separator: 0x2E, omittingEmptySubsequences: false)
                    guard octets.count == 4, octets.allSatisfy({ octet in
                        !octet.isEmpty && octet.count <= 3 && octet.allSatisfy(isDigit) && (octet.count == 1 || octet.first != 0x30) &&
                            (Int(String(decoding: octet, as: UTF16.self)) ?? 256) <= 255
                    }) else { return false }
                    groups += 2
                } else {
                    guard (1...4).contains(part.count), part.allSatisfy(isHex) else { return false }
                    groups += 1
                }
            }
        }
        return halves.count == 2 ? groups <= 7 : groups == 8
    }

    private static func authorityAddress(scheme: String, _ units: [UInt16], from start: Int) -> Address? {
        let content = units.lastIndex { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }.map { $0 + 1 } ?? 0
        let stop = max(start, content)
        let end = units[start..<stop].firstIndex { [0x2F, 0x5C, 0x3F, 0x23].contains($0) } ?? stop
        var authority = Array(units[start..<end])
        var userInfo = ""
        if let at = authority.firstIndex(of: 0x40) {
            guard authority.lastIndex(of: 0x40) == at, scheme != "file", at + 1 < authority.count else { return nil }
            userInfo = String(decoding: authority[...at], as: UTF16.self)
            authority = Array(authority[(at + 1)...])
        }
        var host = authority, port: [UInt16] = []
        if authority.first == 0x5B {
            guard let close = authority.firstIndex(of: 0x5D), isIPv6(Array(authority[1..<close])) else { return nil }
            host = Array(authority[...close])
            // Uri reads a port after the bracket and passes over anything else there.
            let after = authority[(close + 1)...]
            if after.first == 0x3A { port = Array(after.dropFirst()) }
        } else if let colon = authority.firstIndex(of: 0x3A) {
            host = Array(authority[..<colon])
            port = Array(authority[(colon + 1)...])
            guard host.allSatisfy({ isLetter($0) || isDigit($0) || [0x2D, 0x5F, 0x2E].contains($0) || $0 >= 0x80 }), host.first != 0x2E else { return nil }
        } else {
            guard host.allSatisfy({ isLetter($0) || isDigit($0) || [0x2D, 0x5F, 0x2E].contains($0) || $0 >= 0x80 }), host.first != 0x2E else { return nil }
        }
        let needsHost: Set<String> = ["http", "https", "ftp", "telnet", "net.tcp", "net.pipe", "ws", "wss", "gopher", "nntp"]
        if host.isEmpty && needsHost.contains(scheme) { return nil }
        guard port.allSatisfy(isDigit), port.count <= 5, (Int(String(decoding: port, as: UTF16.self)) ?? 0) <= 65535,
              port.isEmpty || scheme != "file" else { return nil }
        let hostText = String(decoding: host, as: UTF16.self).lowercased()
        let portText = String(decoding: port, as: UTF16.self)
        let shownPort = portText.isEmpty || defaultPorts[scheme].map({ Int($0) == Int(portText) }) == true ? "" : ":" + String(Int(portText) ?? 0)
        let rest = Array(units[end...]).map { $0 == 0x5C ? 0x2F : $0 }
        let address = parts(rest, compress: !["ldap", "gopher", "nntp", "telnet"].contains(scheme))
        return Address(host: hostText, path: address.path, fragment: address.fragment, pathAndQuery: address.path + address.query,
                       authority: scheme + "://" + userInfo + hostText + shownPort)
    }
}

/// The en-GB collation and string search that .NET's CompareInfo builds on ICU (CloneCollatorWithOptions and
/// GlobalizationNative_IndexOf in System.Globalization.Native's pal_collation.c at .NET 10), using the macOS ICU library
/// that .NET itself loads on a Mac. IgnoreCase is secondary strength; with IgnoreNonSpace it is primary. Below tertiary
/// strength .NET adds rules that keep hiragana and katakana, and half- and full-width forms, apart, and with IgnoreCase it
/// lets full-width capitals equal their small letters again. Searches use .NET's grapheme rules without the CR LF rule.
private final class KeywordCollation: @unchecked Sendable {
    #if KEYWORD_INDEX_WITHOUT_ICU
    // The model test is also built this way, to cover the fallback used if the system's ICU library cannot be loaded.
    static let shared: KeywordCollation? = nil
    #else
    static let shared = KeywordCollation()
    #endif

    private typealias Status = Int32
    private typealias OpenFunction = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<Status>?) -> OpaquePointer?
    private typealias RulesFunction = @convention(c) (OpaquePointer?, UnsafeMutablePointer<Int32>?) -> UnsafePointer<UInt16>?
    private typealias OpenRulesFunction = @convention(c) (UnsafePointer<UInt16>?, Int32, Int32, Int32, UnsafeMutableRawPointer?, UnsafeMutablePointer<Status>?) -> OpaquePointer?
    private typealias AttributeFunction = @convention(c) (OpaquePointer?, Int32, Int32, UnsafeMutablePointer<Status>?) -> Void
    private typealias CloseFunction = @convention(c) (OpaquePointer?) -> Void
    private typealias CollateFunction = @convention(c) (OpaquePointer?, UnsafePointer<UInt16>?, Int32, UnsafePointer<UInt16>?, Int32) -> Int32
    private typealias BreakRulesFunction = @convention(c) (UnsafePointer<UInt16>?, Int32, UnsafePointer<UInt16>?, Int32, UnsafeMutableRawPointer?, UnsafeMutablePointer<Status>?) -> OpaquePointer?
    private typealias OpenSearchFunction = @convention(c) (UnsafePointer<UInt16>?, Int32, UnsafePointer<UInt16>?, Int32, OpaquePointer?, OpaquePointer?, UnsafeMutablePointer<Status>?) -> OpaquePointer?
    private typealias TextFunction = @convention(c) (OpaquePointer?, UnsafePointer<UInt16>?, Int32, UnsafeMutablePointer<Status>?) -> Void
    private typealias FirstFunction = @convention(c) (OpaquePointer?, UnsafeMutablePointer<Status>?) -> Int32
    private typealias UpperFunction = @convention(c) (Int32) -> Int32

    private let collate: CollateFunction
    private let openBreakRules: BreakRulesFunction
    private let closeBreak: CloseFunction
    private let openSearch: OpenSearchFunction
    private let setText: TextFunction
    private let first: FirstFunction
    private let closeSearch: CloseFunction
    private let toUpper: UpperFunction
    private let searchCollator: OpaquePointer
    private let orderCollator: OpaquePointer
    private let breakRules: [UInt16]?
    private let lock = NSLock()

    private init?() {
        guard let library = dlopen("/usr/lib/libicucore.A.dylib", RTLD_NOW | RTLD_LOCAL) else { return nil }
        func symbol<T>(_ name: String, _ type: T.Type) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: type) } }
        guard let open = symbol("ucol_open", OpenFunction.self), let rulesOf = symbol("ucol_getRules", RulesFunction.self),
              let openRules = symbol("ucol_openRules", OpenRulesFunction.self), let setAttribute = symbol("ucol_setAttribute", AttributeFunction.self),
              let closeCollator = symbol("ucol_close", CloseFunction.self), let collate = symbol("ucol_strcoll", CollateFunction.self),
              let openBreakRules = symbol("ubrk_openRules", BreakRulesFunction.self), let closeBreak = symbol("ubrk_close", CloseFunction.self),
              let openSearch = symbol("usearch_openFromCollator", OpenSearchFunction.self), let setText = symbol("usearch_setText", TextFunction.self),
              let first = symbol("usearch_first", FirstFunction.self), let closeSearch = symbol("usearch_close", CloseFunction.self),
              let toUpper = symbol("u_toupper", UpperFunction.self) else { return nil }
        var status: Status = 0
        guard let base = open("en_GB", &status), status <= 0 else { return nil }
        defer { closeCollator(base) }
        var length: Int32 = 0
        var rules = rulesOf(base, &length).map { Array(UnsafeBufferPointer(start: $0, count: Int(length))) } ?? []
        rules += Self.customRules
        func collator(strength: Int32) -> OpaquePointer? {
            var status: Status = 0
            // UCOL_DEFAULT normalisation, then UCOL_STRENGTH (attribute 5) set again, as .NET does.
            guard let made = rules.withUnsafeBufferPointer({ openRules($0.baseAddress, Int32($0.count), -1, strength, nil, &status) }) else { return nil }
            if status <= 0 { setAttribute(made, 5, strength, &status) }
            if status > 0 { closeCollator(made); return nil }
            return made
        }
        guard let search = collator(strength: 0) else { return nil }
        guard let order = collator(strength: 1) else { closeCollator(search); return nil }
        self.collate = collate; self.openBreakRules = openBreakRules; self.closeBreak = closeBreak; self.openSearch = openSearch
        self.setText = setText; self.first = first; self.closeSearch = closeSearch; self.toUpper = toUpper
        searchCollator = search; orderCollator = order
        // CreateCustomizedBreakIterator: the rules for newer ICU, else those for older versions, else ICU's own breaks.
        breakRules = [Self.breakRulesNew, Self.breakRulesOld].map { Array($0.utf16) }.first { rules in
            var status: Status = 0
            var empty: UInt16 = 0
            guard let breaker = rules.withUnsafeBufferPointer({ openBreakRules($0.baseAddress, Int32($0.count), &empty, 0, nil, &status) }) else { return false }
            closeBreak(breaker)
            return status <= 0
        }
    }

    /// ICU's simple upper-case mapping of a scalar.
    func upper(_ scalar: UInt32) -> UInt32 { UInt32(bitPattern: toUpper(Int32(bitPattern: scalar))) }

    /// CompareInfo.Compare with CompareOptions.IgnoreCase in the en-GB culture.
    func compare(_ left: [UInt16], _ right: [UInt16]) -> Int {
        Int(Self.withBuffer(left) { a in Self.withBuffer(right) { b in collate(orderCollator, a.0, a.1, b.0, b.1) } })
    }

    /// Runs `body` with a test for whether CompareInfo.IndexOf, ignoring case and non-spacing marks, finds `pattern` in a
    /// text. Nil if ICU cannot search.
    func search<Result>(_ pattern: [UInt16], _ body: (([UInt16]) -> Bool) -> Result) -> Result? {
        lock.lock(); defer { lock.unlock() }
        return Self.withBuffer(pattern) { (patternStart, patternLength) -> Result? in
            var status: Status = 0
            var empty: UInt16 = 0
            let breaker = breakRules.flatMap { rules in rules.withUnsafeBufferPointer { openBreakRules($0.baseAddress, Int32($0.count), &empty, 0, nil, &status) } }
            if status > 0 { status = 0 }
            guard let search = openSearch(patternStart, patternLength, patternStart, patternLength, searchCollator, breaker, &status), status <= 0 else {
                if let breaker { closeBreak(breaker) }
                return nil
            }
            defer { closeSearch(search); if let breaker { closeBreak(breaker) } }
            return body { text in
                // An empty source is an equality check, since ICU cannot search one.
                guard !text.isEmpty else { return Self.withBuffer([]) { empty in collate(searchCollator, patternStart, patternLength, empty.0, empty.1) == 0 } }
                return text.withUnsafeBufferPointer { buffer in
                    var status: Status = 0
                    setText(search, buffer.baseAddress, Int32(buffer.count), &status)
                    return status <= 0 && first(search, &status) >= 0
                }
            }
        }
    }

    private static func withBuffer<Result>(_ units: [UInt16], _ body: ((UnsafePointer<UInt16>, Int32)) -> Result) -> Result {
        if units.isEmpty { var zero: UInt16 = 0; return withUnsafePointer(to: &zero) { body(($0, 0)) } }
        return units.withUnsafeBufferPointer { body(($0.baseAddress!, Int32($0.count))) }
    }

    private static let customRules: [UInt16] = {
        var rules: [UInt16] = []
        // FillIgnoreKanaRules without IgnoreKanaType: each hiragana sorts just before its katakana.
        for hiragana in hiraganaWithoutVoicedSoundMark { rules += [0x26, hiragana, 0x3C, hiragana + 0x60] }
        // FillIgnoreWidthRules without IgnoreWidth: each half-width form sorts just before its full-width form...
        for (lower, higher) in zip(halfFullLower, halfFullHigher) {
            rules.append(0x26)
            if (0x21...0x2F).contains(lower) || (0x3A...0x40).contains(lower) || (0x5B...0x60).contains(lower) || (0x7B...0x7E).contains(lower) { rules.append(0x5C) }
            rules += [lower, 0x3C, higher]
        }
        // ...and, with IgnoreCase, each full-width small letter equals its capital.
        for capital in UInt16(0xFF21)...0xFF3A { rules += [0x26, capital + 0x20, 0x3D, capital] }
        // "&a=a" makes ICU apply the last real rule.
        return rules + [0x26, 0x61, 0x3D, 0x61]
    }()

    private static let halfFullLower: [UInt16] = [
        0x0021, 0x0022, 0x0023, 0x0024, 0x0025, 0x0026, 0x0027, 0x0028, 0x0029, 0x002A, 0x002B, 0x002C,
        0x002D, 0x002E, 0x002F, 0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037, 0x0038,
        0x0039, 0x003A, 0x003B, 0x003C, 0x003D, 0x003E, 0x003F, 0x0040, 0x0041, 0x0042, 0x0043, 0x0044,
        0x0045, 0x0046, 0x0047, 0x0048, 0x0049, 0x004A, 0x004B, 0x004C, 0x004D, 0x004E, 0x004F, 0x0050,
        0x0051, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057, 0x0058, 0x0059, 0x005A, 0x005B, 0x005D,
        0x005E, 0x005F, 0x0060, 0x0061, 0x0062, 0x0063, 0x0064, 0x0065, 0x0066, 0x0067, 0x0068, 0x0069,
        0x006A, 0x006B, 0x006C, 0x006D, 0x006E, 0x006F, 0x0070, 0x0071, 0x0072, 0x0073, 0x0074, 0x0075,
        0x0076, 0x0077, 0x0078, 0x0079, 0x007A, 0x007B, 0x007C, 0x007D, 0x007E, 0x00A2, 0x00A3, 0x00AC,
        0x00AF, 0x00A6, 0x00A5, 0x20A9, 0x3002, 0x300C, 0x300D, 0x3001, 0x30FB, 0x30F2, 0x30A1, 0x30A3,
        0x30A5, 0x30A7, 0x30A9, 0x30E3, 0x30E5, 0x30E7, 0x30C3, 0x30A2, 0x30A4, 0x30A6, 0x30A8, 0x30AA,
        0x30AB, 0x30AD, 0x30AF, 0x30B1, 0x30B3, 0x30B5, 0x30B7, 0x30B9, 0x30BB, 0x30BD, 0x30BF, 0x30C1,
        0x30C4, 0x30C6, 0x30C8, 0x30CA, 0x30CB, 0x30CC, 0x30CD, 0x30CE, 0x30CF, 0x30D2, 0x30D5, 0x30D8,
        0x30DB, 0x30DE, 0x30DF, 0x30E0, 0x30E1, 0x30E2, 0x30E4, 0x30E6, 0x30E8, 0x30E9, 0x30EA, 0x30EB,
        0x30EC, 0x30ED, 0x30EF, 0x30F3, 0x3164, 0x3131, 0x3132, 0x3133, 0x3134, 0x3135, 0x3136, 0x3137,
        0x3138, 0x3139, 0x313A, 0x313B, 0x313C, 0x313D, 0x313E, 0x313F, 0x3140, 0x3141, 0x3142, 0x3143,
        0x3144, 0x3145, 0x3146, 0x3147, 0x3148, 0x3149, 0x314A, 0x314B, 0x314C, 0x314D, 0x314E, 0x314F,
        0x3150, 0x3151, 0x3152, 0x3153, 0x3154, 0x3155, 0x3156, 0x3157, 0x3158, 0x3159, 0x315A, 0x315B,
        0x315C, 0x315D, 0x315E, 0x315F, 0x3160, 0x3161, 0x3162, 0x3163
    ]
    private static let halfFullHigher: [UInt16] = [
        0xFF01, 0xFF02, 0xFF03, 0xFF04, 0xFF05, 0xFF06, 0xFF07, 0xFF08, 0xFF09, 0xFF0A, 0xFF0B, 0xFF0C,
        0xFF0D, 0xFF0E, 0xFF0F, 0xFF10, 0xFF11, 0xFF12, 0xFF13, 0xFF14, 0xFF15, 0xFF16, 0xFF17, 0xFF18,
        0xFF19, 0xFF1A, 0xFF1B, 0xFF1C, 0xFF1D, 0xFF1E, 0xFF1F, 0xFF20, 0xFF21, 0xFF22, 0xFF23, 0xFF24,
        0xFF25, 0xFF26, 0xFF27, 0xFF28, 0xFF29, 0xFF2A, 0xFF2B, 0xFF2C, 0xFF2D, 0xFF2E, 0xFF2F, 0xFF30,
        0xFF31, 0xFF32, 0xFF33, 0xFF34, 0xFF35, 0xFF36, 0xFF37, 0xFF38, 0xFF39, 0xFF3A, 0xFF3B, 0xFF3D,
        0xFF3E, 0xFF3F, 0xFF40, 0xFF41, 0xFF42, 0xFF43, 0xFF44, 0xFF45, 0xFF46, 0xFF47, 0xFF48, 0xFF49,
        0xFF4A, 0xFF4B, 0xFF4C, 0xFF4D, 0xFF4E, 0xFF4F, 0xFF50, 0xFF51, 0xFF52, 0xFF53, 0xFF54, 0xFF55,
        0xFF56, 0xFF57, 0xFF58, 0xFF59, 0xFF5A, 0xFF5B, 0xFF5C, 0xFF5D, 0xFF5E, 0xFFE0, 0xFFE1, 0xFFE2,
        0xFFE3, 0xFFE4, 0xFFE5, 0xFFE6, 0xFF61, 0xFF62, 0xFF63, 0xFF64, 0xFF65, 0xFF66, 0xFF67, 0xFF68,
        0xFF69, 0xFF6A, 0xFF6B, 0xFF6C, 0xFF6D, 0xFF6E, 0xFF6F, 0xFF71, 0xFF72, 0xFF73, 0xFF74, 0xFF75,
        0xFF76, 0xFF77, 0xFF78, 0xFF79, 0xFF7A, 0xFF7B, 0xFF7C, 0xFF7D, 0xFF7E, 0xFF7F, 0xFF80, 0xFF81,
        0xFF82, 0xFF83, 0xFF84, 0xFF85, 0xFF86, 0xFF87, 0xFF88, 0xFF89, 0xFF8A, 0xFF8B, 0xFF8C, 0xFF8D,
        0xFF8E, 0xFF8F, 0xFF90, 0xFF91, 0xFF92, 0xFF93, 0xFF94, 0xFF95, 0xFF96, 0xFF97, 0xFF98, 0xFF99,
        0xFF9A, 0xFF9B, 0xFF9C, 0xFF9D, 0xFFA0, 0xFFA1, 0xFFA2, 0xFFA3, 0xFFA4, 0xFFA5, 0xFFA6, 0xFFA7,
        0xFFA8, 0xFFA9, 0xFFAA, 0xFFAB, 0xFFAC, 0xFFAD, 0xFFAE, 0xFFAF, 0xFFB0, 0xFFB1, 0xFFB2, 0xFFB3,
        0xFFB4, 0xFFB5, 0xFFB6, 0xFFB7, 0xFFB8, 0xFFB9, 0xFFBA, 0xFFBB, 0xFFBC, 0xFFBD, 0xFFBE, 0xFFC2,
        0xFFC3, 0xFFC4, 0xFFC5, 0xFFC6, 0xFFC7, 0xFFCA, 0xFFCB, 0xFFCC, 0xFFCD, 0xFFCE, 0xFFCF, 0xFFD2,
        0xFFD3, 0xFFD4, 0xFFD5, 0xFFD6, 0xFFD7, 0xFFDA, 0xFFDB, 0xFFDC
    ]
    private static let hiraganaWithoutVoicedSoundMark: [UInt16] = [
        0x3041, 0x3042, 0x3043, 0x3044, 0x3045, 0x3046, 0x3047, 0x3048, 0x3049, 0x304A, 0x304B, 0x304D,
        0x304F, 0x3051, 0x3053, 0x3055, 0x3057, 0x3059, 0x305B, 0x305D, 0x305F, 0x3061, 0x3063, 0x3064,
        0x3066, 0x3068, 0x306A, 0x306B, 0x306C, 0x306D, 0x306E, 0x306F, 0x3072, 0x3075, 0x3078, 0x307B,
        0x307E, 0x307F, 0x3080, 0x3081, 0x3082, 0x3083, 0x3084, 0x3085, 0x3086, 0x3087, 0x3088, 0x3089,
        0x308A, 0x308B, 0x308C, 0x308D, 0x308E, 0x308F, 0x3090, 0x3091, 0x3092, 0x3093, 0x3095, 0x3096,
        0x309D
    ]
    private static let breakRulesNew = #"""
!!quoted_literals_only; 
$CR          = [\p{Grapheme_Cluster_Break = CR}]; 
$LF          = [\p{Grapheme_Cluster_Break = LF}]; 
$Control     = [[\p{Grapheme_Cluster_Break = Control}]]; 
$Extend      = [[\p{Grapheme_Cluster_Break = Extend}]]; 
$ZWJ         = [\p{Grapheme_Cluster_Break = ZWJ}]; 
$Regional_Indicator = [\p{Grapheme_Cluster_Break = Regional_Indicator}]; 
$Prepend     = [\p{Grapheme_Cluster_Break = Prepend}]; 
$SpacingMark = [\p{Grapheme_Cluster_Break = SpacingMark}]; 
$Virama      = [\p{Gujr}\p{sc=Telu}\p{sc=Mlym}\p{sc=Orya}\p{sc=Beng}\p{sc=Deva}&\p{Indic_Syllabic_Category=Virama}]; 
$LinkingConsonant = [\p{Gujr}\p{sc=Telu}\p{sc=Mlym}\p{sc=Orya}\p{sc=Beng}\p{sc=Deva}&\p{Indic_Syllabic_Category=Consonant}]; 
$ExtCccZwj   = [[\p{gcb=Extend}-\p{ccc=0}] \p{gcb=ZWJ}]; 
$L           = [\p{Grapheme_Cluster_Break = L}]; 
$V           = [\p{Grapheme_Cluster_Break = V}]; 
$T           = [\p{Grapheme_Cluster_Break = T}]; 
$LV          = [\p{Grapheme_Cluster_Break = LV}]; 
$LVT         = [\p{Grapheme_Cluster_Break = LVT}]; 
$Extended_Pict = [:ExtPict:]; 
!!chain; 
!!lookAheadHardBreak; 
$L ($L | $V | $LV | $LVT); 
($LV | $V) ($V | $T); 
($LVT | $T) $T; 
[^$Control $CR $LF] ($Extend | $ZWJ); 
[^$Control $CR $LF] $SpacingMark; 
$Prepend [^$Control $CR $LF]; 
$LinkingConsonant $ExtCccZwj* $Virama $ExtCccZwj* $LinkingConsonant; 
$Extended_Pict $Extend* $ZWJ $Extended_Pict; 
^$Prepend* $Regional_Indicator $Regional_Indicator / $Regional_Indicator; 
^$Prepend* $Regional_Indicator $Regional_Indicator; 
.;
"""#
    private static let breakRulesOld = #"""
$CR          = [\p{Grapheme_Cluster_Break = CR}]; 
$LF          = [\p{Grapheme_Cluster_Break = LF}]; 
$Control     = [\p{Grapheme_Cluster_Break = Control}]; 
$Extend      = [\p{Grapheme_Cluster_Break = Extend}]; 
$SpacingMark = [\p{Grapheme_Cluster_Break = SpacingMark}]; 
$Regional_Indicator = [\p{Grapheme_Cluster_Break = Regional_Indicator}]; 
$L       = [\p{Grapheme_Cluster_Break = L}]; 
$V       = [\p{Grapheme_Cluster_Break = V}]; 
$T       = [\p{Grapheme_Cluster_Break = T}]; 
$LV      = [\p{Grapheme_Cluster_Break = LV}]; 
$LVT     = [\p{Grapheme_Cluster_Break = LVT}]; 
!!chain; 
!!forward; 
$L ($L | $V | $LV | $LVT); 
($LV | $V) ($V | $T); 
($LVT | $T) $T; 
$Regional_Indicator $Regional_Indicator; 
[^$Control $CR $LF] $Extend; 
[^$Control $CR $LF] $SpacingMark; 
!!reverse; 
($L | $V | $LV | $LVT) $L; 
($V | $T) ($LV | $V); 
$T ($LVT | $T); 
$Regional_Indicator $Regional_Indicator; 
$Extend      [^$Control $CR $LF]; 
$SpacingMark [^$Control $CR $LF]; 
!!safe_reverse; 
!!safe_forward; 
"""#
}

/// A JSON value as System.Text.Json's JsonDocument presents it: the last of repeated member names wins, numbers keep
/// their text, and strings keep their UTF-16 units so that an unpaired surrogate can be reported for its field.
private indirect enum JSONValue: Sendable {
    case object([(key: [UInt16], value: JSONValue)])
    case array([JSONValue])
    case string([UInt16])
    case number(String)
    case boolean(Bool)
    case null

    func member(_ name: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        let key = Array(name.utf16)
        return members.last { $0.key == key }?.value
    }
}

/// RFC 8259 as JsonDocument.Parse reads it by default: no comments, no trailing commas, at most 64 levels of nesting.
private struct StrictJSON {
    struct Malformed: Error {}
    private let units: [UInt16]
    private var index = 0
    private var depth = 0

    init(_ units: [UInt16]) { self.units = units }

    mutating func document() throws -> JSONValue {
        skipSpace()
        let value = try value()
        skipSpace()
        guard index == units.count else { throw Malformed() }
        return value
    }

    private mutating func skipSpace() {
        while index < units.count, [0x20, 0x09, 0x0A, 0x0D].contains(units[index]) { index += 1 }
    }

    private mutating func value() throws -> JSONValue {
        guard index < units.count else { throw Malformed() }
        switch units[index] {
        case 0x7B: return try object()
        case 0x5B: return try array()
        case 0x22: return .string(try string())
        case 0x74: try literal("true"); return .boolean(true)
        case 0x66: try literal("false"); return .boolean(false)
        case 0x6E: try literal("null"); return .null
        default: return .number(try number())
        }
    }

    private mutating func nest() throws {
        depth += 1
        guard depth <= 64 else { throw Malformed() }
    }

    private mutating func object() throws -> JSONValue {
        try nest(); defer { depth -= 1 }
        index += 1; skipSpace()
        var members: [(key: [UInt16], value: JSONValue)] = []
        if index < units.count, units[index] == 0x7D { index += 1; return .object(members) }
        while true {
            guard index < units.count, units[index] == 0x22 else { throw Malformed() }
            let key = try string()
            skipSpace()
            guard index < units.count, units[index] == 0x3A else { throw Malformed() }
            index += 1; skipSpace()
            members.append((key, try value()))
            skipSpace()
            guard index < units.count else { throw Malformed() }
            if units[index] == 0x2C { index += 1; skipSpace(); continue }
            guard units[index] == 0x7D else { throw Malformed() }
            index += 1
            return .object(members)
        }
    }

    private mutating func array() throws -> JSONValue {
        try nest(); defer { depth -= 1 }
        index += 1; skipSpace()
        var items: [JSONValue] = []
        if index < units.count, units[index] == 0x5D { index += 1; return .array(items) }
        while true {
            items.append(try value())
            skipSpace()
            guard index < units.count else { throw Malformed() }
            if units[index] == 0x2C { index += 1; skipSpace(); continue }
            guard units[index] == 0x5D else { throw Malformed() }
            index += 1
            return .array(items)
        }
    }

    private mutating func string() throws -> [UInt16] {
        index += 1
        var result: [UInt16] = []
        while index < units.count {
            let unit = units[index]; index += 1
            switch unit {
            case 0x22: return result
            case 0x5C:
                guard index < units.count else { throw Malformed() }
                let escape = units[index]; index += 1
                switch escape {
                case 0x22, 0x5C, 0x2F: result.append(escape)
                case 0x62: result.append(0x08)
                case 0x66: result.append(0x0C)
                case 0x6E: result.append(0x0A)
                case 0x72: result.append(0x0D)
                case 0x74: result.append(0x09)
                case 0x75:
                    guard index + 4 <= units.count else { throw Malformed() }
                    var code: UInt16 = 0
                    for digit in units[index..<index + 4] {
                        switch digit {
                        case 0x30...0x39: code = code << 4 | (digit - 0x30)
                        case 0x41...0x46: code = code << 4 | (digit - 0x37)
                        case 0x61...0x66: code = code << 4 | (digit - 0x57)
                        default: throw Malformed()
                        }
                    }
                    index += 4
                    result.append(code)
                default: throw Malformed()
                }
            default:
                guard unit >= 0x20 else { throw Malformed() }
                result.append(unit)
            }
        }
        throw Malformed()
    }

    private mutating func number() throws -> String {
        let start = index
        func digits() -> Int { let first = index; while index < units.count, (0x30...0x39).contains(units[index]) { index += 1 }; return index - first }
        if index < units.count, units[index] == 0x2D { index += 1 }
        guard index < units.count else { throw Malformed() }
        if units[index] == 0x30 { index += 1 } else { guard (0x31...0x39).contains(units[index]) else { throw Malformed() }; _ = digits() }
        if index < units.count, units[index] == 0x2E { index += 1; guard digits() > 0 else { throw Malformed() } }
        if index < units.count, units[index] == 0x65 || units[index] == 0x45 {
            index += 1
            if index < units.count, units[index] == 0x2B || units[index] == 0x2D { index += 1 }
            guard digits() > 0 else { throw Malformed() }
        }
        return String(utf16CodeUnits: Array(units[start..<index]), count: index - start)
    }

    private mutating func literal(_ word: String) throws {
        let expected = Array(word.utf16)
        guard index + expected.count <= units.count, Array(units[index..<index + expected.count]) == expected else { throw Malformed() }
        index += expected.count
    }
}
