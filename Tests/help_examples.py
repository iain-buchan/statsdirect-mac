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

menu = json.load(open(ROOT / 'Content/analysis-menu.json'))['operations']
def operations_by_page():
    by_page = {}
    for name, entry in menu.items():
        h = entry.get('help')
        if h: by_page.setdefault(h.replace('Help/', ''), []).append(name)
    return by_page

# Column names appear in the instructions as "marked X", "the X column", "select X and Y", in quotes.
QUOTED = re.compile(r'["“”]([^"“”\n]{1,60})["“”]|[‘’]([^‘’\n]{1,60})[‘’]')
STRAIGHT = re.compile(r"(?<![A-Za-z])'([^'\n]{1,60})'(?![A-Za-z])")   # 'Correlation' and 'Sample size' on pages without double quotes
def quoted_names(text):
    names = [a or b for a, b in QUOTED.findall(text)]
    return names if names else STRAIGHT.findall(text)
def quoted_spans(text):
    spans = [(m.start(), m.end(), m.group(1) or m.group(2)) for m in QUOTED.finditer(text)]
    return spans if spans else [(m.start(), m.end(), m.group(1)) for m in STRAIGHT.finditer(text)]
MENU_SENTENCE = re.compile(r'(?:Then |then |Now )?select (?:the )?([A-Za-z0-9\-()/ ]{3,60}?) from the ([A-Za-z0-9\-&/ ]+?) section of the (?:analysis|Analysis) menu', re.I)
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
        columns = [c.strip() for c in quoted_names(instructions)]
        expected = ''
        if j > 0:
            rest = text[j + len('For this example'):]
            # The printed output ends at the next section of prose: a reference list, a menu location or a long sentence.
            m = re.search(r'\n(References|Technical validation|menu location|Menu location|See also|Copyright|R code|Run this|# |[^\n]*<-)', rest)
            expected = rest[:m.start()] if m else rest[:6000]
        # A page may go on to a second example: another "select X from the Y section of the analysis menu"
        # inside the printed output starts its own instructions and figures, for the operation it names.
        parts = [(expected, None)]
        second = MENU_SENTENCE.search(expected, 200)
        if second:
            start = expected.rfind('\n\n', 0, second.start()); start = 0 if start < 0 else start
            parts = [(expected[:start], None), (expected[start:], second.group(1).strip())]
        for index, (block, named) in enumerate(parts):
            if index == 0:
                out.append({'page': rel, 'operations': by_page.get(rel, []), 'columns': columns, 'instructions': instructions[:1500], 'expected': block.strip(),
                            'numbers': NUMBER.findall(block)})
            else:
                k = block.find('For this example'); instr2 = block[:k] if k > 0 else block[:800]; block2 = block[k + len('For this example'):] if k > 0 else ''
                ops = [name for name, entry in menu.items() if entry.get('title') and (named.lower() in entry['title'].lower() or entry['title'].lower() in named.lower())]
                out.append({'page': rel + '#2', 'operations': ops, 'columns': [c.strip() for c in quoted_names(instr2)], 'instructions': instr2[:1500], 'expected': block2.strip(),
                            'numbers': NUMBER.findall(block2)})
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
