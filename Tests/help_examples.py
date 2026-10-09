"""The worked examples of the help: which pages use the test workbook, the columns they name, the
operation each page documents (from the analysis menu's help links) and the output printed under
"For this example:". Shared by the replay test and its coverage report."""
import glob, html, json, re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
HELP = ROOT / 'Content/Help'

def page_text(path):
    t = Path(path).read_text(errors='replace')
    t = re.sub(r'<script.*?</script>', '', t, flags=re.S)
    t = re.sub(r'</(p|div|h[1-6]|li|tr|table)>', '\n', t, flags=re.I)
    t = re.sub(r'<br\s*/?>', '\n', t, flags=re.I)
    x = re.sub(r'<[^>]+>', ' ', t)
    x = html.unescape(x).replace('\xa0', ' ')
    return '\n'.join(re.sub(r'[ \t]+', ' ', line).strip() for line in x.split('\n'))

def operations_by_page():
    menu = json.load(open(ROOT / 'Content/analysis-menu.json'))['operations']
    by_page = {}
    for name, entry in menu.items():
        h = entry.get('help')
        if h: by_page.setdefault(h.replace('Help/', ''), []).append(name)
    return by_page

# Column names appear in the instructions as "marked X", "the X column", "select X and Y", in quotes.
QUOTED = re.compile(r'[\"“”]([^\"“”\n]{1,60})[\"“”]')
NUMBER = re.compile(r'(?<![\w.])-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?(?![\w.])')

def examples():
    by_page = operations_by_page()
    out = []
    for path in sorted(glob.glob(str(HELP / '*/*.htm'))):
        rel = str(Path(path).relative_to(HELP))
        text = page_text(path)
        if 'test workbook' not in text: continue
        i = text.find('test workbook')
        # The instructions run from the sentence with "test workbook" to "For this example:".
        j = text.find('For this example', i)
        instructions = text[i:j] if j > i else text[i:i + 1200]
        columns = [c.strip() for c in QUOTED.findall(instructions)]
        expected = ''
        if j > 0:
            rest = text[j + len('For this example'):]
            # The printed output ends at the next section of prose: a reference list, a menu location or a long sentence.
            m = re.search(r'\n(References|Technical validation|menu location|Menu location|See also|Copyright|R code|Run this|# |[^\n]*<-)', rest)
            expected = rest[:m.start()] if m else rest[:6000]
        out.append({'page': rel, 'operations': by_page.get(rel, []), 'columns': columns, 'instructions': instructions[:1500], 'expected': expected.strip(),
                    'numbers': NUMBER.findall(expected)})
    return out

if __name__ == '__main__':
    import openpyxl
    wb = openpyxl.load_workbook(ROOT / 'FullEngine/Upstream/StatsDirectUI/Assets/Data/test.xlsx', read_only=True)
    titles = {}
    for ws in wb.worksheets:
        for c in next(ws.iter_rows(min_row=1, max_row=1)):
            if c.value is not None: titles.setdefault(str(c.value).strip().lower(), ws.title)
    rows = examples()
    print(f'{len(rows)} pages use the test workbook; {sum(1 for r in rows if r["expected"])} print an example output; {sum(1 for r in rows if r["operations"])} are reached from the analysis menu')
    for r in rows:
        known = [c for c in r['columns'] if c.lower() in titles]
        print(f"{r['page']:55s} ops={','.join(r['operations'])[:40]:40s} cols={len(r['columns'])}/{len(known)} numbers={len(r['numbers'])}")
