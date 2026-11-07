import Foundation

@main
struct HelpKeywordIndexTests {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }
    static var checks = 0
    static func check(_ value: Bool, _ message: String) throws {
        checks += 1
        guard value else { throw Failure(errorDescription: message) }
    }
    static func run() throws {
        let manager = FileManager.default
        let scratch = URL(fileURLWithPath:manager.currentDirectoryPath).appendingPathComponent(".build/help-keyword-index-" + UUID().uuidString)
        let root = scratch.appendingPathComponent("help")
        try manager.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? manager.removeItem(at:scratch) }
        func file(_ relative: String, text: String = "<html><body>Topic</body></html>") throws {
            let path = root.appendingPathComponent(relative)
            try manager.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data(text.utf8).write(to:path)
        }
        let map = root.appendingPathComponent("keyword-index.json")
        func write(_ value: Any) throws {
            try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.fragmentsAllowed]).write(to:map)
        }
        func entry(_ term: String = "Keyword", _ title: String = "Topic", _ path: String = "basics/one.htm") -> [String: Any] {
            ["term":term,"title":title,"path":path]
        }
        func index(_ entries: [Any]) throws { try write(["schemaVersion":1,"entries":entries]) }
        func rejected(_ value: Any, _ message: String) throws {
            try write(value)
            do { _ = try HelpKeywordIndex.load(root:root); throw Failure(errorDescription:message) }
            catch is HelpKeywordIndex.IndexError { checks += 1 }
        }

        try check(try HelpKeywordIndex.load(root:root) == nil,"A legacy bundle has no invented index")
        for path in ["basics/one.htm","basics/two.htm","basics/space name.htm","basics/unindexed.htm","index.html","resources/unsafe.htm","Data/unsafe.htm"] {
            try file(path)
        }
        try index([
            entry("Gaussian distribution","Normal distribution"),
            entry("gaussian distribution","Ignored duplicate","BASICS/ONE.HTM"),
            entry("AI assistance","Report window"), entry("AI assistance","Script window","basics/two.htm"),
            entry("Duplicate","Same title"), entry("Duplicate","Same title","basics/two.htm"),
            entry("Scheffé","Accented method"), entry("A title match","Université"),
            entry("Spaced target","An anchor","basics/space%20name.htm#an%20anchor")
        ])
        guard let catalog = try HelpKeywordIndex.load(root:root) else { throw Failure(errorDescription:"The authored map was not loaded") }
        try check(catalog.entries.count == 8,"Duplicate term/target pairs are collapsed while ambiguous targets survive")
        try check(catalog.rows.count == 8,"Every term/target has one picker row")
        try check(catalog.filteredRows("GAUSSIAN").count == 1,"Keyword filtering ignores English case")
        try check(catalog.filteredRows("scheffe").first?.entry.term == "Scheffé","Keyword filtering ignores accents")
        try check(catalog.filteredRows("UNIVERSITE").first?.entry.term == "A title match","Filtering includes target titles with case/diacritic folding")
        try check(catalog.filteredRows("  ").count == catalog.rows.count,"A whitespace filter shows the whole authored index")
        try check(catalog.filteredRows("__nothing__").isEmpty,"No matches leave no selectable target")
        try check(catalog.filteredRows("unindexed").isEmpty,"Page titles outside the keyword map are never invented as index entries")
        let alternatives = catalog.filteredRows("AI assistance")
        try check(alternatives.map(\.text) == ["AI assistance — Report window","AI assistance — Script window"],"Multiple targets append their titles in English order")
        let duplicateTitles = catalog.filteredRows("Duplicate")
        try check(duplicateTitles.map(\.text) == ["Duplicate — Same title (basics/one.htm)","Duplicate — Same title (basics/two.htm)"],"Duplicate titles append their distinct paths")
        try check(duplicateTitles.allSatisfy(\.showPath),"The selected-topic detail can show disambiguating paths")
        try check(alternatives.allSatisfy { !$0.showPath },"Unique target titles need no path suffix")
        try check(catalog.entries.first(where: { $0.term == "Spaced target" })?.path == "basics/space%20name.htm#an%20anchor","Local paths and anchors retain correct URL escaping")
        try check(catalog.entries.first(where: { $0.term == "Gaussian distribution" })?.title == "Normal distribution","Duplicate suppression retains the original authored label")
        try check(catalog.rows == (try HelpKeywordIndex.load(root:root))?.rows,"Repeated loading produces deterministic order")

        try file("basics/a.htm")
        try file("basics/_.htm")
        try index([entry("Ordinal","Same title","basics/_.htm"),entry("Ordinal","Same title","basics/a.htm")])
        try check((try HelpKeywordIndex.load(root:root))?.entries.map(\.path) == ["basics/a.htm","basics/_.htm"],"Tied target titles use Windows ordinal case-insensitive path ordering")

        try index([])
        try check((try HelpKeywordIndex.load(root:root))?.rows.isEmpty == true,"An explicitly empty authored map is valid")
        for value: Any in [[], ["entries":[]], ["schemaVersion":2,"entries":[]], ["schemaVersion":true,"entries":[]],
                           ["schemaVersion":"1","entries":[]], ["schemaVersion":1,"entries":[:]]] {
            try rejected(value,"An unsupported/malformed schema was accepted")
        }
        try Data("{\"schemaVersion\":1.0,\"entries\":[]}".utf8).write(to:map)
        do { _ = try HelpKeywordIndex.load(root:root); throw Failure(errorDescription:"A decimal schema token was accepted") }
        catch is HelpKeywordIndex.IndexError { checks += 1 }
        for value: Any in [NSNull(),"entry",["term":"Keyword","title":"Topic"],entry(" "),entry("Keyword","\n"),["term":42,"title":"Topic","path":"basics/one.htm"]] {
            try rejected(["schemaVersion":1,"entries":[value]],"A malformed entry was accepted")
        }
        for path in ["https://example.org/topic.htm","//example.org/topic.htm","/basics/one.htm","../one.htm","basics/../one.htm",
                     "%2e%2e/one.htm","basics\\one.htm","basics%5cone.htm","file:basics/one.htm","basics/one.htm?x=1",
                     "index.html","resources/unsafe.htm","Data/unsafe.htm","basics/one.txt","missing.htm","basics//one.htm",
                     "basics/one.htm\0","basics/%ZZ.htm","basics/one.htm#bad%ZZ","#anchor"] {
            try rejected(["schemaVersion":1,"entries":[entry("Keyword","Topic",path)]],"An unsafe/missing topic was accepted: " + path)
        }
        try Data("{broken".utf8).write(to:map)
        do { _ = try HelpKeywordIndex.load(root:root); throw Failure(errorDescription:"Malformed JSON was accepted") }
        catch is HelpKeywordIndex.IndexError { checks += 1 }

        let outside = scratch.appendingPathComponent("outside.htm")
        try Data("<html><body>Outside</body></html>".utf8).write(to:outside)
        try manager.createSymbolicLink(at:root.appendingPathComponent("linked.htm"),withDestinationURL:outside)
        try rejected(["schemaVersion":1,"entries":[entry("Link","Outside","linked.htm")]],"A linked topic was accepted")
        try manager.createSymbolicLink(at:root.appendingPathComponent("linked-folder"),withDestinationURL:root.appendingPathComponent("basics"))
        try rejected(["schemaVersion":1,"entries":[entry("Link","Inside","linked-folder/one.htm")]],"A linked directory was accepted")
        try manager.removeItem(at:map)
        try manager.createSymbolicLink(at:map,withDestinationURL:outside)
        do { _ = try HelpKeywordIndex.load(root:root); throw Failure(errorDescription:"A linked keyword map was accepted") }
        catch is HelpKeywordIndex.IndexError { checks += 1 }
        try manager.removeItem(at:map)
        try manager.createDirectory(at:map,withIntermediateDirectories:false)
        do { _ = try HelpKeywordIndex.load(root:root); throw Failure(errorDescription:"A directory keyword map was accepted") }
        catch is HelpKeywordIndex.IndexError { checks += 1 }

        if CommandLine.arguments.count > 1 {
            let actualRoot = URL(fileURLWithPath:CommandLine.arguments[1])
            guard let actual = try HelpKeywordIndex.load(root:actualRoot) else { throw Failure(errorDescription:"The private generated keyword map is missing") }
            try check(actual.entries.count == 726,"The private generated map retains all 726 term/targets")
            try check(Set(actual.entries.map(\.term)).count == 719,"The private generated map retains all 719 distinct terms")
            try check(Set(actual.entries.map(\.path)).count == 255,"The private generated map retains all 255 indexed topics")
            try check(actual.filteredRows("ipynb").contains { $0.entry.term == "Jupyter notebook files (.ipynb)" },"The corrected Jupyter label is available")
            try check(actual.filteredRows("test.xlsx").contains { $0.entry.term == "Example workbook (test.xlsx)" },"The corrected example workbook label is available")
            try check(actual.filteredRows("metafor").contains { $0.entry.term == "R package: metafor" },"The corrected R package label is available")
        }
    }
    static func main() {
        do { try run(); print("PASS: \(checks) help keyword index model checks") }
        catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
}
