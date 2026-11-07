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
        /// Windows's message for the rule, word for word (HelpCatalog.LoadIndexEntries at Windows d783a494).
        func refusal(_ text: String, aliases: HelpKeywordIndex.Aliases = [:]) -> String? {
            do { try Data(text.utf8).write(to:map); _ = try HelpKeywordIndex.load(root:root,aliases:aliases); return nil }
            catch { return error.localizedDescription }
        }
        func refused(_ text: String, _ expected: String, _ label: String, aliases: HelpKeywordIndex.Aliases = [:]) throws {
            let actual = refusal(text,aliases:aliases)
            try check(actual == expected,"\(label): \(actual ?? "accepted")")
        }
        /// The stored path of a one-entry map whose target is `path`, or the refusal.
        func stored(_ path: String, aliases: HelpKeywordIndex.Aliases = [:]) -> String {
            do {
                try write(["schemaVersion":1,"entries":[entry("Keyword","Topic",path)]])
                return try HelpKeywordIndex.load(root:root,aliases:aliases)?.entries.map(\.path).joined(separator:" ;; ") ?? "no index"
            } catch { return error.localizedDescription }
        }
        func json(_ value: Any) -> String { String(data:try! JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.fragmentsAllowed]),encoding:.utf8)! }

        try check(try HelpKeywordIndex.load(root:root) == nil,"A legacy bundle has no invented index")
        for path in ["basics/one.htm","basics/two.htm","basics/space name.htm","basics/unindexed.htm","index.html","resources/unsafe.htm","Data/unsafe.htm"] {
            try file(path)
        }
        try index([
            entry("Gaussian distribution","Normal distribution"),
            entry("gaussian distribution","Ignored duplicate","BASICS/one.htm"),
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
        for path in ["https://example.org/topic.htm","//example.org/topic.htm","../one.htm","basics/../one.htm",
                     "%2e%2e/one.htm","basics\\one.htm","basics%5cone.htm","file:basics/one.htm",
                     "index.html","resources/unsafe.htm","Data/unsafe.htm","basics/one.txt","missing.htm",
                     "basics/one.htm\0","basics/%ZZ.htm","#anchor","basics/one.HTM","BASICS/ONE.HTM"] {
            try rejected(["schemaVersion":1,"entries":[entry("Keyword","Topic",path)]],"An unsafe/missing topic was accepted: " + path)
        }
        let resolved: [(String,String)] = [("/basics/one.htm","basics/one.htm"),("Content/basics/one.htm","basics/one.htm"),
                                           ("basics/one.htm?x=1","basics/one.htm"),("basics/one.htm?x=1#part","basics/one.htm#part"),
                                           ("basics//one.htm","basics//one.htm"),("basics/one.htm#bad%ZZ","basics/one.htm#bad%25ZZ"),
                                           ("BASICS/one.htm","BASICS/one.htm"),("one_alias","basics/one.htm"),("1001","basics/one.htm")]
        for (path,stored) in resolved {
            try write(["schemaVersion":1,"entries":[entry("Keyword","Topic",path)]])
            let loaded = try HelpKeywordIndex.load(root:root,aliases:["ONE_ALIAS":"basics/one.htm","1001":"basics/one.htm"])
            try check(loaded?.entries.map(\.path) == [stored],"Windows's Resolve accepts \(path) as \(stored): \(loaded?.entries.map(\.path) ?? [])")
        }
        let unsafeTarget = "Help keyword index entry 1 refers to a missing or unsafe topic."
        let notPackaged = "Help keyword index entry 1 does not name a packaged topic."
        for (path,message) in [("https://example.org/topic.htm",notPackaged),("file:///C:/test.htm",notPackaged),("C:/test.htm",notPackaged),
                               ("//example.org/topic.htm",notPackaged),("basics\\one.htm",notPackaged),("basics/one.htm\u{0}",notPackaged),
                               ("../one.htm",unsafeTarget),("%2e%2e/one.htm",unsafeTarget),("missing.htm",unsafeTarget),
                               ("index.html",unsafeTarget),("resources/unsafe.htm",unsafeTarget),("basics/one.HTM",unsafeTarget)] {
            try refused(json(["schemaVersion":1,"entries":[entry("Keyword","Topic",path)]]),message,"Windows's message for " + path)
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
        try check(!HelpKeywordIndex.exists(root:root) && (try HelpKeywordIndex.load(root:root)) == nil,"A folder named keyword-index.json is no index, as Windows's File.Exists finds")
        try manager.removeItem(at:map)

        // System.Text.Json's JsonDocument, as Windows reads the map.
        let schema = "The help keyword index has an unsupported or missing schema. Rebuild the desktop help."
        let invalid = "The help keyword index contains invalid JSON. Rebuild the desktop help."
        let valid = #"{"term":"Keyword","title":"Topic","path":"basics/one.htm"}"#
        try refused(#"{"schemaVersion":1,"entries":[\#(valid),]}"#,invalid,"A trailing comma in the entries is invalid JSON")
        try refused(#"{"schemaVersion":1,"entries":[],}"#,invalid,"A trailing comma in the object is invalid JSON")
        try refused("{\"schemaVersion\":1,/* note */\"entries\":[]}",invalid,"A comment is invalid JSON")
        try refused(String(repeating:"[",count:65) + String(repeating:"]",count:65),invalid,"Nesting deeper than 64 levels is invalid JSON")
        try refused(#"{"schemaVersion":1,"schemaVersion":2,"entries":[]}"#,schema,"The last of repeated member names wins, so a repeated version 2 is refused")
        try check(refusal(#"{"schemaVersion":2,"schemaVersion":1,"entries":[]}"#) == nil,"The last of repeated member names wins, so a repeated version 1 is read")
        for root in ["5","\"text\"","null","[]","{\"schemaVersion\":1.0,\"entries\":[]}","{\"schemaVersion\":1e0,\"entries\":[]}","{\"schemaVersion\":true,\"entries\":[]}"] {
            try refused(root,schema,"Windows's schema message for " + root)
        }
        try refused(#"{"schemaVersion":1,"entries":[{"term":"\ud800","title":"Title","path":"basics/one.htm"}]}"#,"Help keyword index entry 1 has invalid term text.","An unpaired surrogate is invalid text")
        try refused(#"{"schemaVersion":1,"entries":[{"term":" ","title":"Title","path":"basics/one.htm"}]}"#,"Help keyword index entry 1 has no valid term.","A blank term is refused")
        try refused(#"{"schemaVersion":1,"entries":[{"term":"Term","title":5,"path":"basics/one.htm"}]}"#,"Help keyword index entry 1 has no valid title.","A number title is refused")
        try refused(#"{"schemaVersion":1,"entries":[{"term":"Term","title":"Title","path":null}]}"#,"Help keyword index entry 1 has no valid path.","A null path is refused")
        try refused(#"{"schemaVersion":1,"entries":[null]}"#,"Help keyword index entry 1 has no valid term.","A null entry is refused")
        for (mark,encoding) in [([0xEF,0xBB,0xBF] as [UInt8],String.Encoding.utf8),([0xFF,0xFE],.utf16LittleEndian),([0xFE,0xFF],.utf16BigEndian)] {
            try (Data(mark) + #"{"schemaVersion":1,"entries":[\#(valid)]}"#.data(using:encoding)!).write(to:map)
            try check((try HelpKeywordIndex.load(root:root))?.entries.count == 1,"A byte-order mark selects the text encoding, as File.ReadAllText does")
        }

        // Windows's own fixture (KeywordIndexChecks.cs at Windows 5e877405): aliases collapse, English order, text kept.
        try file("alpha.htm"); try file("beta.htm")
        try write(["schemaVersion":1,"entries":[["term":"beta keyword","title":"Beta topic","path":"beta.htm"],
                                                ["term":"Alpha keyword","title":"Beta topic","path":"beta.htm"],
                                                ["term":"Alpha keyword","title":"Alpha topic","path":"alpha.htm"],
                                                ["term":"ALPHA KEYWORD","title":"Duplicate alias","path":"ALPHA_ALIAS"],
                                                ["term":"Numbers & symbols < 5","title":"Title \"quoted\" & plain","path":"alpha.htm#section"]]])
        let windows = try HelpKeywordIndex.load(root:root,aliases:["ALPHA":"alpha.htm","ALPHA_ALIAS":"alpha.htm","BETA":"beta.htm","1001":"alpha.htm","1002":"alpha.htm","1003":"beta.htm"])
        try check(windows?.entries.count == 4,"Index metadata is available and duplicate term-target aliases collapse")
        try check(windows?.entries.map(\.term) == ["Alpha keyword","Alpha keyword","beta keyword","Numbers & symbols < 5"] && windows?.entries.first?.title == "Alpha topic" && windows?.entries[1].title == "Beta topic","Index sorts English keywords and target titles without changing displayed case")
        try check(windows?.entries.last.map { $0.title == "Title \"quoted\" & plain" && $0.path == "alpha.htm#section" } == true,"Index retains JSON text and authored target fragments without interpreting HTML")

        try write(["schemaVersion":1,"entries":[entry("Zeta","1"),entry("alpha","2"),entry("Beta","3")]])
        try check((try HelpKeywordIndex.load(root:root))?.entries.map(\.term) == ["alpha","Beta","Zeta"],"Keywords sort in English order whatever their case")

        // Windows's ICU search at primary strength equates compatibility forms, typographic apostrophes and æ, œ and ß.
        try write(["schemaVersion":1,"entries":[entry("I² (meta-analysis)"),entry("Cohen's kappa"),entry("Haenszel"),entry("ﬁnite","Topic"),entry("Paired t test")]])
        let folding = try HelpKeywordIndex.load(root:root)!
        #if KEYWORD_INDEX_WITHOUT_ICU
        // Without the system's ICU library the filter still ignores case and accents but folds nothing more.
        try check(folding.filteredRows("PAIRED T").count == 1 && folding.filteredRows("cohen's").count == 1 && folding.filteredRows("I2").isEmpty,
                  "Without ICU the filter ignores case and accents only")
        #else
        try check(folding.filteredRows("I2").map(\.entry.term) == ["I² (meta-analysis)"],"I2 finds I², as on Windows")
        try check(folding.filteredRows("Cohen\u{2019}s").map(\.entry.term) == ["Cohen's kappa"],"A typographic apostrophe finds the straight one, as on Windows")
        try check(folding.filteredRows("hæn").map(\.entry.term) == ["Haenszel"] && folding.filteredRows("fin").map(\.entry.term) == ["ﬁnite"],"æ matches ae and ﬁ matches fi, as on Windows")
        try check(folding.filteredRows("t-test").isEmpty && folding.filteredRows("paired t").count == 1,"Hyphens and spaces stay distinct, as on Windows")
        #endif


        #if !KEYWORD_INDEX_WITHOUT_ICU
        // The rest of Windows's ICU search, as .NET 10 answers it here: full-width forms, the prime and the modifier
        // apostrophe stay apart, a spacing accent alone finds nothing, letters with strokes find their base letters,
        // ignorable characters are skipped, and a combining mark alone, like an empty search, finds everything.
        try write(["schemaVersion":1,"entries":[entry("ANOVA"),entry("Cohen's kappa"),entry("Bjørn test"),entry("co\u{AD}operation"),entry("t test"),entry("Łódź")]])
        let icu = try HelpKeywordIndex.load(root:root)!
        try check(icu.filteredRows("ａｎｏｖａ").isEmpty && icu.filteredRows("ＡＮＯＶＡ").isEmpty,"Full-width letters find nothing, as Windows matches without ignoring width")
        try check(icu.filteredRows("Cohen\u{2032}s").isEmpty && icu.filteredRows("Cohen\u{2BC}s").isEmpty,"The prime and the modifier apostrophe are not apostrophes, as on Windows")
        try check(icu.filteredRows("Cohen\u{201A}s").map(\.entry.term) == ["Cohen's kappa"],"U+201A matches the apostrophe, as on Windows")
        try check(icu.filteredRows("\u{B4}").isEmpty && icu.filteredRows("t\u{B4}test").isEmpty,"A spacing accent alone finds nothing, as on Windows")
        try check(icu.filteredRows("Bjorn").count == 1 && icu.filteredRows("Lodz").count == 1,"Letters with strokes match their base letters, as on Windows")
        try check(icu.filteredRows("cooperation").count == 1,"A soft hyphen in a keyword is skipped, as on Windows")
        try check(icu.filteredRows("\u{301}").count == icu.rows.count && icu.filteredRows("\u{200B}").count == icu.rows.count,"An ignorable query matches every entry, as Windows's empty match does")
        try check(HelpKeywordIndex.trimmedQuery(" \u{3000}kappa\u{A0}\u{2028}") == "kappa" && HelpKeywordIndex.trimmedQuery("\u{200B}") == "\u{200B}","The filter trims .NET's white space, which does not include U+200B")

        // HelpCatalog's order: en-GB ignoring case, ß after ss and full-width forms after their letters, then path.
        try write(["schemaVersion":1,"entries":[entry("Gauß","a"),entry("Gauss","b"),entry("Gaust","c"),entry("Straße","d"),entry("Strasse","e"),entry("Strassf","f"),
                                                entry("Ａ","g"),entry("ＡＮＯＶＡ","h"),entry("apriori","i"),entry("A","j"),entry("ANOVA","k"),entry("b","l")]])
        try check((try HelpKeywordIndex.load(root:root))?.entries.map(\.term) == ["A","ANOVA","apriori","Ａ","ＡＮＯＶＡ","b","Gauss","Gauß","Gaust","Strasse","Straße","Strassf"],
                  "Keywords sort as Windows's en-GB comparer orders them")
        #endif
        // Ordinal case-insensitive keys: canonical equivalents, ẞ and ß stay apart; σ and ς, µ and μ are one key.
        for (pair,count) in [(["Té","Te\u{301}"],2),(["Tẞ","Tß"],2),(["Tσ","Tς"],1),(["Tµ","Tμ"],1),(["ı","I"],2),(["ſ","S"],2)] {
            try write(["schemaVersion":1,"entries":pair.map { entry($0,"T","basics/one.htm") }])
            try check((try HelpKeywordIndex.load(root:root))?.entries.count == count,"\(pair) are \(count) keywords for one page, as Windows's OrdinalIgnoreCase finds")
        }
        try write(["schemaVersion":1,"entries":[entry("Gσ","Other","basics/one.htm"),entry("Gς","Topic","basics/two.htm")]])
        try check(Set((try HelpKeywordIndex.load(root:root))?.rows.map(\.text) ?? []) == ["Gσ — Other","Gς — Topic"],"σ and ς group as one keyword, as on Windows")

        // HelpCatalog.Resolve's messages and System.Uri's forms, as .NET 10 gives them.
        try file("sym/a[b].htm"); try file("co\u{AD}op.htm"); try file("zw\u{200C}nj.htm")
        let invalidPath = "Help keyword index entry 1 has an invalid topic path."
        for (path,message) in [("Content//basics/one.htm",unsafeTarget),("Content//index.html",unsafeTarget),("Content/%2Fresources%2Funsafe.htm",unsafeTarget),
                               ("Content///basics/one.htm",unsafeTarget),("basics/one.htm%00",invalidPath),("%00basics/one.htm",invalidPath),
                               ("C:basics/one.htm",unsafeTarget),("https:basics/one.htm",unsafeTarget),("http:",unsafeTarget),("file:/basics/one.htm",unsafeTarget),("a:b",unsafeTarget),
                               ("mailto:",notPackaged),("urn:x",notPackaged),("x:/",notPackaged),("javascript:x",notPackaged),("\u{200B}https://x/one.htm",unsafeTarget),
                               ("//\u{301}x",notPackaged),("basics/one\u{1}.htm",unsafeTarget),("basics/one|.htm",unsafeTarget),
                               ("http://[:]/one.htm",unsafeTarget),("http://[::::]/one.htm",unsafeTarget),("http://[1::2::3]/one.htm",unsafeTarget),
                               ("http://[1:2:3:4:5:6:7:8:9]/one.htm",unsafeTarget),("http://[::1.2.3.256]/one.htm",unsafeTarget),("ab://[:]/x",unsafeTarget),
                               ("http://[::1]/one.htm",notPackaged),("http://[1:2:3:4:5:6:1.2.3.4]/one.htm",notPackaged),("http://[fe80::1%25en0]/one.htm",notPackaged),
                               ("http://[::1]x/one.htm",notPackaged),("http://[::1]:0080/one.htm",notPackaged),("http://[::1]:65536/one.htm",unsafeTarget)] {
            try refused(json(["schemaVersion":1,"entries":[entry("Keyword","Topic",path)]]),message,"Windows's message for " + path)
        }
        for (path,expected) in [("basics//one.htm","basics//one.htm"),("Content/basics//one.htm","basics//one.htm"),("basics/one.htm#\u{301}x","basics/one.htm#%CC%81x"),
                                ("basics/one.htm#\u{200D}x","basics/one.htm#%E2%80%8Dx"),("basics/one.htm?\u{301}x#y","basics/one.htm#y"),("basics/one.htm#a#\u{301}b","basics/one.htm#a#%CC%81b"),
                                ("sym/a[b].htm","sym/a[b].htm"),("sym/a%5Bb%5D.htm","sym/a[b].htm"),("basics/one.htm#a[b]","basics/one.htm#a[b]"),("basics/one.htm#frag#more","basics/one.htm#frag#more"),
                                ("basics/one.htm#%41","basics/one.htm#A"),("basics/one.htm#%7e","basics/one.htm#~"),("basics/one.htm#%c3%a9","basics/one.htm#%C3%A9"),("basics/one.htm#%e9","basics/one.htm#%e9"),
                                ("basics/one.htm#x%3ey","basics/one.htm#x%3ey"),("basics/one.htm#x%3e\u{E9}y","basics/one.htm#x%3E%C3%A9y"),("basics/one.htm#\u{200B}","basics/one.htm#%E2%80%8B"),
                                ("co%C2%ADop.htm","co%C2%ADop.htm"),("co\u{AD}op.htm","co%C2%ADop.htm"),("zw\u{200C}nj.htm","zw%E2%80%8Cnj.htm")] {
            let actual = stored(path)
            try check(actual == expected,"Windows stores \(path) as \(expected): \(actual)")
        }
        // White space is .NET's: a keyword of U+200B alone is not blank.
        try write(["schemaVersion":1,"entries":[entry("\u{200B}"),entry("Keyword\u{200B}","Topic","basics/two.htm")]])
        try check((try HelpKeywordIndex.load(root:root))?.entries.count == 2,"U+200B is no white space to Windows, so such keywords are kept")

        // File.ReadAllText removes one byte-order mark and replaces malformed text with U+FFFD.
        let body = #"{"schemaVersion":1,"entries":[\#(valid)]}"#
        try (Data([0xEF,0xBB,0xBF,0xEF,0xBB,0xBF]) + Data(body.utf8)).write(to:map)
        try check(refusal(String(decoding:try Data(contentsOf:map),as:UTF8.self)) == invalid,"A second byte-order mark is invalid JSON, as on Windows")
        try (Data([0xFF,0xFE]) + body.data(using:.utf16LittleEndian)! + Data([0x00])).write(to:map)
        do { _ = try HelpKeywordIndex.load(root:root); throw Failure(errorDescription:"UTF-16 text with a dangling byte was accepted") }
        catch let error as HelpKeywordIndex.IndexError { try check(error.localizedDescription == invalid,"UTF-16 text ending in half a character is invalid JSON, as on Windows") }
        var surrogate = Array(body.replacingOccurrences(of:"Keyword",with:"Key#word").utf16)
        surrogate[surrogate.firstIndex(of:0x23)!] = 0xD800
        try (Data([0xFF,0xFE]) + Data(surrogate.flatMap { [UInt8($0 & 0xFF),UInt8($0 >> 8)] })).write(to:map)
        try check((try HelpKeywordIndex.load(root:root))?.entries.first?.term == "Key\u{FFFD}word","An unpaired surrogate in UTF-16 text reads as U+FFFD, as File.ReadAllText reads it")

        // Aliases: Windows's web addresses for a page, and of names that differ only in case the last in Alias.xml.
        try file("alpha.htm"); try file("beta.htm")
        let web: HelpKeywordIndex.Aliases = ["WEB_ALIAS":"https://www.statsdirect.com/help/alpha.htm","BARE_ALIAS":"https://statsdirect.com/help/alpha.htm#sec",
                                             "GH_ALIAS":"https://iain-buchan.github.io/statisticalhelp/beta.htm","LOCAL_ALIAS":"https://help.statsdirect.invalid/alpha.htm?x#y",
                                             "OTHER_ALIAS":"https://example.org/alpha.htm","HELPLESS_ALIAS":"https://www.statsdirect.com/alpha.htm"]
        for (alias,expected) in [("WEB_ALIAS","alpha.htm"),("bare_alias","alpha.htm#sec"),("GH_ALIAS","beta.htm"),("LOCAL_ALIAS","alpha.htm#y"),
                                 ("OTHER_ALIAS",unsafeTarget),("HELPLESS_ALIAS",unsafeTarget)] {
            let actual = stored(alias,aliases:web)
            try check(actual == expected,"Windows resolves \(alias) to \(expected): \(actual)")
        }
        let repeated = HelpKeywordIndex.Aliases([(key:"Kappa",link:"alpha.htm"),(key:"KAPPA",link:"beta.htm"),(key:" ",link:"alpha.htm")])
        try check(stored("kappa",aliases:repeated) == "beta.htm" && stored(" ",aliases:repeated) == "Help keyword index entry 1 has no valid path.","Of alias names that differ only in case the last wins, and a blank name is no alias")

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
    /// .NET 10's own answers, recorded in Tests/help-keyword-index-dotnet10.json (Tests/verification.md says how), so that
    /// a change in .NET, ICU or this code shows here. The ICU parts are left out of the KEYWORD_INDEX_WITHOUT_ICU build.
    static func dotNetAnswers() throws {
        let manager = FileManager.default
        let file = URL(fileURLWithPath:manager.currentDirectoryPath).appendingPathComponent("Tests/help-keyword-index-dotnet10.json")
        guard let data = try? Data(contentsOf:file), let answers = (try? JSONSerialization.jsonObject(with:data)) as? [String: Any],
              let source = answers["source"] as? [String: Any], let runtime = source["runtime"] as? String, let os = source["os"] as? String,
              let icu = source["icu"] as? String, let sortVersion = source["enGBSortVersion"] as? Int else {
            throw Failure(errorDescription:"The .NET 10 answers could not be read from \(file.path)")
        }
        let recorded = "\(runtime) on ICU \(icu), en-GB sort version \(sortVersion), \(os)"
        let here = HelpKeywordIndex.TestHooks.icuVersions
        let thisMac = here.map { "ICU \($0.icu), en-GB sort version \($0.sort)" } ?? "no ICU"
        // Given with every failure of a part that depends on ICU, so that a failure on another macOS can be read.
        let sameICU = here.map { $0.icu == icu && $0.sort == sortVersion } == true
        let icuNote = " This part depends on ICU. The answers were recorded with ICU \(icu), en-GB sort version \(sortVersion), and this Mac has \(thisMac)"
            + (sameICU ? ", the same, so the code or its use of ICU has changed." : ", which differs, so the differences may come from ICU's data rather than the code.")
        func cases(_ section: String, _ member: String = "cases") throws -> [[Any]] {
            guard let rows = (answers[section] as? [String: Any])?[member] as? [[Any]], !rows.isEmpty else {
                throw Failure(errorDescription:"The .NET 10 answers have no \(section) \(member)")
            }
            return rows
        }
        func malformed(_ section: String, _ row: [Any]) -> Failure { Failure(errorDescription:"A malformed \(section) case in the .NET 10 answers: \(row)") }
        /// A recorded string is JSON text, or its UTF-16 code units where it holds U+0000, U+FEFF or an unpaired surrogate.
        func units(_ value: Any) -> [UInt16]? {
            if let text = value as? String { return Array(text.utf16) }
            guard let list = value as? [Int], list.allSatisfy({ (0...0xFFFF).contains($0) }) else { return nil }
            return list.map { UInt16($0) }
        }
        func shown(_ value: [UInt16]?) -> String {
            guard let value else { return "null" }
            return "\"" + value.map { (0x20...0x7E).contains($0) && $0 != 0x5C ? String(UnicodeScalar(UInt8($0))) : String(format:"\\u{%04X}",$0) }.joined() + "\""
        }
        func shown(_ value: String) -> String { shown(Array(value.utf16)) }
        /// One check for a part: every case agrees, or every difference is listed and the part fails.
        func agree(_ differences: [String], of total: Int, _ section: String, icuDependent: Bool = false) throws {
            guard differences.isEmpty else {
                for difference in differences.prefix(200) { print("  \(section) differs: \(difference)") }
                if differences.count > 200 { print("  ... and \(differences.count - 200) more \(section) differences") }
                throw Failure(errorDescription:"\(differences.count) of \(total) \(section) cases differ from \(recorded), as listed above." + (icuDependent ? icuNote : ""))
            }
            try check(true,section)
        }
        var summary: [String] = []

        // HelpCatalog.Resolve's forms of a path and fragment, and the parts it reads from an alias's address.
        let uri = try cases("uriPathAndFragment")
        var differences: [String] = []
        for row in uri {
            guard row.count == 4, let path = units(row[0]), row[1] is NSNull || units(row[1]) != nil,
                  let absolutePath = units(row[2]), let fragmentPart = units(row[3]) else { throw malformed("Uri path and fragment",row) }
            let fragment = units(row[1])
            let actual = HelpKeywordIndex.TestHooks.pathAndFragment(path + (fragment.map { [0x23] + $0 } ?? []))
            if Array(actual.path.utf16) != absolutePath || Array(actual.fragment.utf16) != fragmentPart {
                differences.append("\(shown(path)) # \(shown(fragment)): .NET \(shown(absolutePath)) \(shown(fragmentPart)), Mac \(shown(actual.path)) \(shown(actual.fragment))")
            }
        }
        try agree(differences,of:uri.count,"Uri path and fragment")
        summary.append("\(uri.count) Uri paths and fragments")

        let parts = try cases("aliasAddressParts")
        differences = []
        for row in parts {
            guard row.count == 6, let address = units(row[0]) else { throw malformed("alias address parts",row) }
            let expected = try row[1...].map { value -> [UInt16] in
                guard let part = units(value) else { throw malformed("alias address parts",row) }
                return part
            }
            let text = String(decoding:address,as:UTF16.self)
            guard let actual = HelpKeywordIndex.TestHooks.absoluteAddress(text) else { differences.append("\(shown(text)) is no absolute address on the Mac"); continue }
            let found = [actual.host,actual.path,actual.fragment,actual.authority,actual.pathAndQuery].map { Array($0.utf16) }
            if found != expected {
                differences.append("\(shown(text)): .NET \(expected.map { shown($0) }.joined(separator:" ")), Mac \(found.map { shown($0) }.joined(separator:" "))")
            }
        }
        try agree(differences,of:parts.count,"alias address parts")
        summary.append("\(parts.count) alias addresses' parts")

        // Uri.TryCreate(text, UriKind.Absolute) as on Windows. The one documented difference: .NET also accepts a final
        // IPv4 octet such as 04 in an IPv6 literal, and the Mac does not, so that target gets the other refusal message.
        let documented: Set<String> = ["http://[::1.2.3.04]/one.htm"]
        let absolute = try cases("absoluteAddresses")
        differences = []
        for row in absolute {
            guard row.count == 2, let text = units(row[0]), let answer = row[1] as? Int, answer == 0 || answer == 1 else { throw malformed("absolute address",row) }
            let address = String(decoding:text,as:UTF16.self), accepted = HelpKeywordIndex.TestHooks.absoluteAddress(address) != nil
            if documented.contains(address) ? accepted == (answer == 1) : accepted != (answer == 1) {
                differences.append("\(shown(address)): .NET \(answer == 1 ? "absolute" : "not absolute"), Mac \(accepted ? "absolute" : "not absolute")" + (documented.contains(address) ? " (a documented difference that no longer differs)" : ""))
            }
        }
        try agree(differences,of:absolute.count,"absolute address")
        summary.append("\(absolute.count) absolute or other addresses")

        // String.Compare and StringComparer.OrdinalIgnoreCase, which both builds follow, and the en-GB order, which needs ICU.
        let pairs = try cases("ordinalAndEnglish")
        differences = []
        var english: [String] = []
        for row in pairs {
            guard row.count == 5, let a = units(row[0]), let b = units(row[1]), let order = row[2] as? Int, let equal = row[3] as? Int, let culture = row[4] as? Int,
                  (-1...1).contains(order), equal == 0 || equal == 1, (-1...1).contains(culture) else { throw malformed("comparison",row) }
            let actual = HelpKeywordIndex.TestHooks.ordinalIgnoreCase(a,b)
            if actual.order != order || actual.equal != (equal == 1) {
                differences.append("\(shown(a)) and \(shown(b)): .NET \(order) \(equal == 1), Mac \(actual.order) \(actual.equal)")
            }
            #if !KEYWORD_INDEX_WITHOUT_ICU
            let sign = HelpKeywordIndex.TestHooks.englishOrder(a,b)
            if sign != culture { english.append("\(shown(a)) and \(shown(b)): .NET \(culture), Mac \(sign)") }
            #endif
        }
        // With ICU, OrdinalIgnoreCase takes ICU's simple upper case of each unit, as .NET does.
        try agree(differences,of:pairs.count,"OrdinalIgnoreCase",icuDependent:here != nil)
        summary.append("\(pairs.count) OrdinalIgnoreCase pairs")

        #if KEYWORD_INDEX_WITHOUT_ICU
        try check(!HelpKeywordIndex.TestHooks.usesICU,"The no-ICU build loaded ICU")
        summary.append("the ICU parts skipped")
        #else
        try check(HelpKeywordIndex.TestHooks.usesICU && here != nil,"The system's ICU library did not load, so the ICU parts cannot be compared with .NET 10")
        try agree(english,of:pairs.count,"en-GB IgnoreCase order",icuDependent:true)
        summary.append("\(pairs.count) en-GB orderings")

        // HelpCatalog's order of the shipped map, from a shuffled input, and HelpIndexMenu's filter over it, through
        // load() and filteredRows().
        guard let filter = answers["filter"] as? [String: Any], let map = filter["map"] as? [[String]], let order = filter["order"] as? [Int],
              let listed = filter["hitsListedUpTo"] as? Int, map.allSatisfy({ $0.count == 3 }), map.count == order.count, Set(order) == Set(map.indices) else {
            throw Failure(errorDescription:"The .NET 10 answers have no valid filter map")
        }
        let queries = try cases("filter","queries")
        let scratch = URL(fileURLWithPath:manager.currentDirectoryPath).appendingPathComponent(".build/help-keyword-index-dotnet10-" + UUID().uuidString)
        defer { try? manager.removeItem(at:scratch) }
        for path in Set(map.map { $0[2] }) {
            let page = scratch.appendingPathComponent(path)
            try manager.createDirectory(at:page.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data("<html><body>Topic</body></html>".utf8).write(to:page)
        }
        try JSONSerialization.data(withJSONObject:["schemaVersion":1,"entries":map.map { ["term":$0[0],"title":$0[1],"path":$0[2]] }]).write(to:scratch.appendingPathComponent("keyword-index.json"))
        guard let index = try HelpKeywordIndex.load(root:scratch) else { throw Failure(errorDescription:"The recorded map was not loaded") }
        let sorted = index.entries.map { [$0.term,$0.title,$0.path] }, expectedOrder = order.map { map[$0] }
        let first = sorted.indices.first { $0 >= expectedOrder.count || sorted[$0] != expectedOrder[$0] }
        try check(sorted.count == expectedOrder.count && first == nil,"The \(map.count) entries are not in .NET 10's order" + (first.map { ": entry \($0 + 1) is \(sorted[$0]), .NET has \($0 < expectedOrder.count ? "\(expectedOrder[$0])" : "none")" } ?? ": \(sorted.count) entries") + "." + icuNote)
        var position: [HelpKeywordIndex.Entry: Int] = [:]
        for (offset, entry) in index.entries.enumerated() { position[entry] = offset }
        differences = []
        for row in queries {
            guard let text = units(row[0]), let count = row[1] as? Int, count >= 0 else { throw malformed("keyword filter",row) }
            // The hits themselves are recorded for short answers, and for the rest the count.
            var expected: [Int]?
            if count <= listed {
                guard row.count == 3, let hits = row[2] as? [Int], hits.count == count else { throw malformed("keyword filter",row) }
                expected = hits
            } else if row.count != 2 { throw malformed("keyword filter",row) }
            let query = String(decoding:text,as:UTF16.self), hits = index.filteredRows(query).map { position[$0.entry]! }
            if hits.count != count || expected.map({ $0 != hits }) == true {
                differences.append("\(shown(query)): .NET \(expected.map { "\($0)" } ?? "\(count) hits"), Mac \(expected == nil ? "\(hits.count) hits" : "\(hits)")")
            }
        }
        try agree(differences,of:queries.count,"keyword filter",icuDependent:true)
        summary.append("the order of \(map.count) shuffled entries and \(queries.count) filter queries")
        #endif
        print(".NET 10 answers (recorded with \(recorded); this Mac: \(thisMac)) agree: " + summary.joined(separator:", "))
    }
    static func main() {
        do { try run(); try dotNetAnswers(); print("PASS: \(checks) help keyword index model checks") }
        catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }
}
