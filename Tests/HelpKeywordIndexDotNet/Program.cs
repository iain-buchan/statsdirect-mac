// Recomputes the .NET answers recorded in Tests/help-keyword-index-dotnet10.json from the inputs recorded there and lists
// every difference, so that the answers can be checked again on another .NET, ICU or machine (Tests/verification.md).
//
//   dotnet run --project Tests/HelpKeywordIndexDotNet -c Release -- Tests/help-keyword-index-dotnet10.json [--write]
//
// It makes the .NET calls that Windows's HelpCatalog.cs and HelpIndexMenu.ApplyFilter make (Windows d783a494). Built with
// -p:WindowsHelpCatalog=<Windows checkout>/StatsDirectUI/UI/HtmlHelp/HelpCatalog.cs, the map's order comes from Windows's own
// HelpCatalog.IndexEntries. --write records this run's answers, and this run's .NET and ICU, in the same layout.
// The exit code is 0 when every recorded answer agrees with this run.
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

string file = args.FirstOrDefault(a => !a.StartsWith("--")) ?? "Tests/help-keyword-index-dotnet10.json";
bool write = args.Contains("--write");
J document;
using (var parsed = JsonDocument.Parse(File.ReadAllBytes(file))) document = J.From(parsed.RootElement);
var english = StringComparer.Create(CultureInfo.GetCultureInfo("en-GB"), true);
var info = CultureInfo.GetCultureInfo("en-GB").CompareInfo;
const CompareOptions filterOptions = CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace;
const string origin = "https://help.statsdirect.invalid";
var differences = new List<string>();
var parts = new List<string>();

var source = (JObject)document["source"];
string recorded = $"{J.Text(source["runtime"])} on ICU {J.Text(source["icu"])}, en-GB sort version {((JNumber)source["enGBSortVersion"]).Value}, {J.Text(source["os"])}";
string os = RuntimeInformation.OSDescription + " " + RuntimeInformation.OSArchitecture;
string icu = Probe.IcuVersion();
int sortVersion = info.Version.FullVersion;
#if WINDOWS_HELP_CATALOG
const string orderFrom = "Windows's HelpCatalog.cs";
#else
const string orderFrom = "HelpCatalog's ordering, repeated here";
#endif
Console.WriteLine($"Recorded with {recorded}.");
Console.WriteLine($"This run: {RuntimeInformation.FrameworkDescription} on ICU {icu}, en-GB sort version {sortVersion}, {os}; the map's order from {orderFrom}.");

// Each part's answers for its recorded inputs replace the recorded rows; a row that changes is a difference.
void Check(string part, JObject section, string member, Func<JArray, JArray> answer, bool icuDependent = false)
{
    var rows = (JArray)section[member];
    var answers = rows.Items.Select(row => (J)answer((JArray)row)).ToList();
    int changed = 0;
    for (int i = 0; i < answers.Count; i++)
    {
        if (J.Compact(answers[i]) == J.Compact(rows.Items[i])) continue;
        changed++;
        differences.Add($"{part}: recorded {J.Compact(rows.Items[i])}, this run {J.Compact(answers[i])}");
    }
    parts.Add($"{part}: {answers.Count} cases, " + (changed == 0 ? "all agree" : $"{changed} differ") + (icuDependent ? " (depends on ICU)" : ""));
    section.Set(member, new JArray(answers));
}

// The filter over the shipped map, and HelpCatalog's order of the map's (shuffled) entries.
var filter = (JObject)document["filter"];
var map = ((JArray)filter["map"]).Items.Select(row => (Term: J.Text(row[0]), Title: J.Text(row[1]), Page: J.Text(row[2]))).ToList();
var entries = Probe.IndexEntries(map, english);
var position = map.Select((entry, i) => (entry, i)).ToDictionary(p => p.entry, p => p.i);
var order = new JArray(entries.Select(entry => (J)new JNumber(position[entry])).ToList());
string orderCheck = J.Compact(order) == J.Compact(filter["order"]) ? "agrees" : "DIFFERS";
if (orderCheck != "agrees") differences.Add($"filter order: recorded {J.Compact(filter["order"])}, this run {J.Compact(order)}");
parts.Add($"filter order of {map.Count} entries: {orderCheck} (depends on ICU)");
filter.Set("order", order);
long listed = ((JNumber)filter["hitsListedUpTo"]).Value;
Check("filter", filter, "queries", row =>
{
    string query = J.Text(row[0]).Trim();
    var hits = Enumerable.Range(0, entries.Count).Where(i => query.Length == 0 ||
        info.IndexOf(entries[i].Term, query, filterOptions) >= 0 || info.IndexOf(entries[i].Title, query, filterOptions) >= 0).ToList();
    var answer = new List<J> { row[0], new JNumber(hits.Count) };
    if (hits.Count <= listed) answer.Add(new JArray(hits.Select(h => (J)new JNumber(h)).ToList()));
    return new JArray(answer);
}, icuDependent: true);

// OrdinalIgnoreCase, whose upper case comes from ICU on macOS and Linux, and the en-GB order.
var pairs = (JObject)document["ordinalAndEnglish"];
Check("OrdinalIgnoreCase and en-GB order", pairs, "cases", row =>
{
    string a = J.Text(row[0]), b = J.Text(row[1]);
    return new JArray(new List<J> { row[0], row[1], new JNumber(Math.Sign(string.Compare(a, b, StringComparison.OrdinalIgnoreCase))),
        new JNumber(StringComparer.OrdinalIgnoreCase.Equals(a, b) ? 1 : 0), new JNumber(Math.Sign(english.Compare(a, b))) });
}, icuDependent: true);

// System.Uri's forms of a path and fragment under the help origin, as HelpCatalog.Resolve builds its result.
Check("Uri path and fragment", (JObject)document["uriPathAndFragment"], "cases", row =>
{
    string fragment = row[1] is JNull ? null : J.Text(row[1]);
    try
    {
        var page = new Uri(origin + "/" + J.Text(row[0]) + (fragment != null ? "#" + fragment : ""));
        return new JArray(new List<J> { row[0], row[1], J.Recorded(page.AbsolutePath.TrimStart('/')), J.Recorded(page.Fragment) });
    }
    catch (Exception ex) { return new JArray(new List<J> { row[0], row[1], new JString("EXC " + ex.GetType().Name) }); }
});

// The parts HelpCatalog.Resolve reads from an alias's address.
Check("alias address parts", (JObject)document["aliasAddressParts"], "cases", row =>
{
    if (!Probe.TryCreateAbsolute(J.Text(row[0]), out var address)) return new JArray(new List<J> { row[0], new JString("not absolute") });
    J Part(Func<string> read) { try { return J.Recorded(read()); } catch (Exception ex) { return new JString("EXC " + ex.GetType().Name); } }
    return new JArray(new List<J> { row[0], Part(() => address.Host), Part(() => address.AbsolutePath), Part(() => address.Fragment),
        Part(() => address.GetLeftPart(UriPartial.Authority)), Part(() => address.PathAndQuery) });
});

// Whether text is an absolute address, which HelpCatalog refuses as a keyword target.
Check("absolute addresses", (JObject)document["absoluteAddresses"], "cases",
    row => new JArray(new List<J> { row[0], new JNumber(Probe.TryCreateAbsolute(J.Text(row[0]), out _) ? 1 : 0) }));

foreach (string part in parts) Console.WriteLine("  " + part);
foreach (string difference in differences) Console.WriteLine("DIFFERS " + difference);
if (write)
{
    source.Set("runtime", new JString(RuntimeInformation.FrameworkDescription));
    source.Set("os", new JString(os));
    source.Set("icu", new JString(icu));
    source.Set("enGBSortVersion", new JNumber(sortVersion));
    source.Set("recorded", new JString(DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)));
    File.WriteAllText(file, J.Dump(document, 0) + "\n", new UTF8Encoding(false));
    Console.WriteLine($"Wrote this run's answers to {file}.");
    return 0;
}
Console.WriteLine(differences.Count == 0 ? "Every recorded answer agrees with this run." : $"{differences.Count} recorded answers differ from this run.");
return differences.Count == 0 ? 0 : 1;

static class Probe
{
    /// Uri.TryCreate(text, UriKind.Absolute) as it answers on Windows, where a single leading '/' is no address; .NET on
    /// macOS and Linux reads one as a file path. On Windows this changes nothing.
    internal static bool TryCreateAbsolute(string text, out Uri address)
    {
        if (text.StartsWith('/') && !text.StartsWith("//")) { address = null; return false; }
        return Uri.TryCreate(text, UriKind.Absolute, out address);
    }

    /// HelpCatalog.IndexEntries for the map: Windows's own when built with WindowsHelpCatalog; otherwise, for a map of
    /// plain packaged pages, LoadIndexEntries' trimmed text, each term and page kept once (OrdinalIgnoreCase), then OrderBy
    /// term and ThenBy title with the en-GB comparer ignoring case, and ThenBy page OrdinalIgnoreCase.
    internal static List<(string Term, string Title, string Page)> IndexEntries(List<(string Term, string Title, string Page)> map, StringComparer english)
    {
#if WINDOWS_HELP_CATALOG
        string root = Directory.CreateTempSubdirectory("help-keyword-index-").FullName;
        try
        {
            File.WriteAllText(Path.Combine(root, "index.html"), "<html><body>Help</body></html>");
            Directory.CreateDirectory(Path.Combine(root, "Data"));
            File.WriteAllText(Path.Combine(root, "Data", "Alias.xml"), "<?xml version=\"1.0\" encoding=\"utf-8\"?><CatapultAliasFile />");
            foreach (string page in map.Select(entry => entry.Page.Split('#', '?')[0]).Distinct())
            {
                string full = Path.Combine(root, page);
                Directory.CreateDirectory(Path.GetDirectoryName(full));
                File.WriteAllText(full, "<html><body>Topic</body></html>");
            }
            File.WriteAllText(Path.Combine(root, "keyword-index.json"), JsonSerializer.Serialize(new
            {
                schemaVersion = 1,
                entries = map.Select(entry => new { term = entry.Term, title = entry.Title, path = entry.Page }).ToArray(),
            }));
            return new StatsDirect.UI.HtmlHelp.HelpCatalog(root).IndexEntries.Select(entry => (entry.Term, entry.Title, entry.Path)).ToList();
        }
        finally { Directory.Delete(root, true); }
#else
        foreach (var entry in map)
        {
            string[] segments = entry.Page.Split('/');
            if (entry.Term != entry.Term.Trim() || entry.Title != entry.Title.Trim() || entry.Term.Length == 0 || entry.Title.Length == 0 ||
                !(entry.Page.EndsWith(".htm", StringComparison.Ordinal) || entry.Page.EndsWith(".html", StringComparison.Ordinal)) ||
                segments.Any(s => s.Length == 0 || s is "." or ".." || !s.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-' or '.')))
                throw new InvalidDataException($"Entry {entry} is not a plain packaged page with trimmed text; build with -p:WindowsHelpCatalog=... to use Windows's loader.");
        }
        var seen = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        var kept = new List<(string Term, string Title, string Page)>();
        foreach (var entry in map)
        {
            if (!seen.TryGetValue(entry.Term, out var pages)) seen[entry.Term] = pages = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (pages.Add(entry.Page)) kept.Add(entry);
        }
        return kept.OrderBy(entry => entry.Term, english).ThenBy(entry => entry.Title, english).ThenBy(entry => entry.Page, StringComparer.OrdinalIgnoreCase).ToList();
#endif
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void GetVersion(byte[] version);

    /// u_getVersion of the ICU library .NET uses: the system's libicucore on macOS, icu.dll on Windows.
    internal static string IcuVersion()
    {
        foreach (string name in new[] { "/usr/lib/libicucore.dylib", "icu.dll", "icuuc.dll" })
        {
            if (!NativeLibrary.TryLoad(name, out var library)) continue;
            if (!NativeLibrary.TryGetExport(library, "u_getVersion", out var export)) continue;
            var version = new byte[4];
            Marshal.GetDelegateForFunctionPointer<GetVersion>(export)(version);
            return string.Join(".", version);
        }
        return "unknown";
    }
}

/// The answers file as written: objects keep their members' order, and every number is an integer.
abstract class J
{
    internal static J From(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Object => new JObject(value.EnumerateObject().Select(member => (member.Name, From(member.Value))).ToList()),
        JsonValueKind.Array => new JArray(value.EnumerateArray().Select(From).ToList()),
        JsonValueKind.String => new JString(value.GetString()),
        JsonValueKind.Number => new JNumber(value.GetInt64()),
        JsonValueKind.Null => new JNull(),
        _ => throw new InvalidDataException("Unexpected JSON value: " + value.ValueKind),
    };
    internal J this[string name] => ((JObject)this).Members.First(member => member.Name == name).Value;
    internal J this[int index] => ((JArray)this).Items[index];

    /// A recorded string is JSON text, or its UTF-16 code units where it holds U+0000, U+FEFF or an unpaired surrogate.
    internal static string Text(J value) => value switch
    {
        JString text => text.Value,
        JArray units => new string(units.Items.Select(unit => checked((char)((JNumber)unit).Value)).ToArray()),
        _ => throw new InvalidDataException("Not a recorded string: " + Compact(value)),
    };
    internal static J Recorded(string text)
    {
        bool units = text.Contains('\0') || text.Contains('﻿');
        for (int i = 0; i < text.Length && !units; i++)
        {
            if (char.IsHighSurrogate(text[i]) && i + 1 < text.Length && char.IsLowSurrogate(text[i + 1])) i++;
            else if (char.IsSurrogate(text[i])) units = true;
        }
        return units ? new JArray(text.Select(unit => (J)new JNumber(unit)).ToList()) : new JString(text);
    }

    /// One line, as Python's json.dumps(value, ensure_ascii=True, separators=(",", ":")) writes it.
    internal static string Compact(J value) => value switch
    {
        JString text => Quote(text.Value),
        JNumber number => number.Value.ToString(CultureInfo.InvariantCulture),
        JNull => "null",
        JArray list => "[" + string.Join(",", list.Items.Select(Compact)) + "]",
        JObject members => "{" + string.Join(",", members.Members.Select(member => Quote(member.Name) + ":" + Compact(member.Value))) + "}",
        _ => throw new InvalidOperationException(),
    };
    /// The file's layout: a member to a line, and a list of more than three lists or strings an item to a line.
    internal static string Dump(J value, int indent)
    {
        string pad = new(' ', 2 * indent);
        if (value is JObject members)
            return pad + "{\n" + string.Join(",\n", members.Members.Select(member => pad + "  " + Quote(member.Name) + ": " + Dump(member.Value, indent + 1).TrimStart(' '))) + "\n" + pad + "}";
        if (value is JArray list && list.Items.Count > 3 && list.Items[0] is JArray or JString)
            return pad + "[\n" + string.Join(",\n", list.Items.Select(item => pad + "  " + Compact(item))) + "\n" + pad + "]";
        return pad + Compact(value);
    }
    private static string Quote(string text)
    {
        var quoted = new StringBuilder("\"");
        foreach (char unit in text)
        {
            quoted.Append(unit switch
            {
                '"' => "\\\"", '\\' => "\\\\", '\n' => "\\n", '\r' => "\\r", '\t' => "\\t", '\b' => "\\b", '\f' => "\\f",
                _ => unit < 0x20 || unit > 0x7E ? "\\u" + ((int)unit).ToString("x4", CultureInfo.InvariantCulture) : unit.ToString(),
            });
        }
        return quoted.Append('"').ToString();
    }
}
sealed class JString(string value) : J { internal string Value { get; } = value; }
sealed class JNumber(long value) : J { internal long Value { get; } = value; }
sealed class JNull : J { }
sealed class JArray(List<J> items) : J { internal List<J> Items { get; } = items; }
sealed class JObject(List<(string Name, J Value)> members) : J
{
    internal List<(string Name, J Value)> Members { get; } = members;
    internal void Set(string name, J value) => Members[Members.FindIndex(member => member.Name == name)] = (name, value);
}
