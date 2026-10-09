"""Output frames carry the Windows worksheet placement, so the form can write them into the worksheet as Windows does."""
import glob, re
from pathlib import Path
from test_menu import Session, columns
ROOT = Path(__file__).resolve().parents[1]
s = Session()
try:
    # The start snapshot says whether the operation writes a frame and where Windows would put it (the
    # definition's default-placement; AfterSelection when unstated).
    expected = {}
    for f in glob.glob(str(ROOT / 'FullEngine/Upstream/StatsDirectUI/Assets/Operations/*.xml')):
        text = Path(f).read_text(errors='replace')
        if '<output-frame' in text:
            m = re.search(r'default-placement="(\w+)"', text); expected[Path(f).stem] = m.group(1) if m else 'AfterSelection'
    assert len(expected) >= 60 and 'ReplaceSelection' in expected.values() and 'BeforeSelection' in expected.values(), len(expected)
    before = sorted(k for k, v in expected.items() if v == 'BeforeSelection')[0]; replace = sorted(k for k, v in expected.items() if v == 'ReplaceSelection')[0]
    for name, placement in [('TransformLog', 'AfterSelection'), (replace, 'ReplaceSelection'), (before, 'BeforeSelection')]:
        id, st = s.start(name); assert st['writesWorksheet'] is True and st['placement'] == placement, (name, st.get('writesWorksheet'), st.get('placement')); s.close(id)
    id, st = s.start('OneWay'); assert st['writesWorksheet'] is False and st['placement'] is None, st; s.close(id)
    print('PASS: operations that write a worksheet frame say so at the start, with the Windows default placement')
    # Each frame carries its own placement, keep-selection, missing indicator, formula flag and the variables' lengths.
    result = s.run('FillSeries', {'rows': 5, 'startval': 10, 'formula': 'X+2', 'title': 'Independent series'})
    frame = result['frames'][0]
    assert frame['placement'] == 'AfterSelection' and frame['keepSelection'] is False and frame['missingIndicator'] == '*' and frame['formulae'] is False and frame['lengths'] == [5], frame
    result = s.run('TransformLog', {'data': columns([1, 2, 4, 8])})
    frame = result['frames'][0]
    assert frame['lengths'] == [4] and frame['columns'] == 1 and [c['text'] for c in frame['cells'] if c['row'] == 1] == ['0'], frame
    print('PASS: output frames carry the Windows placement, keep-selection, missing indicator and variable lengths')
finally:
    s.finish()
