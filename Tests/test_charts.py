"""Chart geometry from the engine's SVG renderer: for each chart type a small data set is drawn and the
marks are read back through the axes' own tick labels, so every point, bar, box, whisker, error bar,
step and limit line sits where the data say it should. Complements test_agreement.py, which checks
the agreement plot the same way."""
import html as H, re
import xml.etree.ElementTree as ET
from test_menu import Session, columns

def chart(s, operation, answers):
    r = s.run(operation, answers)
    assert 'Chart not drawn' not in r['html'], (operation, re.findall(r'Chart not drawn[^<]*', r['html']))
    m = re.search(r'<svg\b[\s\S]*?</svg>', r['html']); assert m, operation
    return Chart(ET.fromstring(m[0]), re.sub(r'\s+', ' ', H.unescape(re.sub(r'<[A-Za-z/!][^>]*>', ' ', r['html']))))

class Chart:
    def __init__(self, root, text):
        self.root, self.text = root, text
        self.width, self.height = map(float, root.get('viewBox').split()[2:])
        self.items = []   # (tag, attributes, absolute dx, dy)
        def walk(el, dx, dy):
            m = re.search(r'translate\(\s*([-\d.]+)[,\s]+([-\d.]+)\s*\)', el.get('transform') or '')
            if m: dx += float(m.group(1)); dy += float(m.group(2))
            self.items.append((el.tag.split('}')[-1], el, dx, dy))
            for child in el: walk(child, dx, dy)
        walk(root, 0, 0)
        self.labels = [(''.join(el.itertext()).strip(), float(el.get('x', 0)) + dx, float(el.get('y', 0)) + dy) for tag, el, dx, dy in self.items if tag == 'text']
        self.check_bounds()
    def check_bounds(self):
        for tag, el, dx, dy in self.items:
            for key in ('x', 'y', 'cx', 'cy', 'x1', 'y1', 'x2', 'y2'):
                if key in el.attrib:
                    v = float(el.attrib[key]) + (dx if 'x' in key else dy); limit = self.width if 'x' in key else self.height
                    assert -1 <= v <= limit + 1, (tag, key, v, limit)
    def marks(self, tag): return [(el, dx, dy) for t, el, dx, dy in self.items if t == tag]
    def points(self):
        return [(float(el.get('cx')) + dx, float(el.get('cy')) + dy) for el, dx, dy in self.marks('ellipse')]
    def rects(self):
        return [(float(el.get('x')) + dx, float(el.get('y')) + dy, float(el.get('width')), float(el.get('height'))) for el, dx, dy in self.marks('rect')]
    def lines(self):
        return [(float(el.get('x1')) + dx, float(el.get('y1')) + dy, float(el.get('x2')) + dx, float(el.get('y2')) + dy) for el, dx, dy in self.marks('line')]
    def numeric_labels(self):
        out = []
        for text, x, y in self.labels:
            try: out.append((float(text), x, y))
            except ValueError: pass
        return out
    def ticks(self, which):
        """The numeric tick labels of one axis: those sharing a baseline (x axis) or a left edge (y axis), as (value, coordinate)."""
        groups = {}
        for value, x, y in self.numeric_labels():
            key = round(y) if which == 'x' else round(x)
            groups.setdefault(key, []).append((value, x if which == 'x' else y))
        ticks = max(groups.values(), key=len)
        assert len(ticks) >= 3, (which, groups)
        return ticks
    def axis(self, which):
        """A linear map from data value to pixel along one axis, fitted to its tick labels; the fit must be exact to the pixel."""
        ticks = self.ticks(which)
        values = [v for v, _ in ticks]; coords = [c for _, c in ticks]
        n = len(ticks); mv = sum(values) / n; mc = sum(coords) / n
        slope = sum((v - mv) * (c - mc) for v, c in ticks) / sum((v - mv) ** 2 for v in values)
        intercept = mc - slope * mv
        for v, c in ticks: assert abs(intercept + slope * v - c) <= 1.0, (which, v, c, intercept + slope * v)
        return lambda v: intercept + slope * v
    def has_line(self, x1, y1, x2, y2, tolerance=1.5):
        return any((abs(a - x1) <= tolerance and abs(b - y1) <= tolerance and abs(c - x2) <= tolerance and abs(d - y2) <= tolerance) or
                   (abs(a - x2) <= tolerance and abs(b - y2) <= tolerance and abs(c - x1) <= tolerance and abs(d - y1) <= tolerance) for a, b, c, d in self.lines())

def near(a, b, tolerance=1.5): return abs(a - b) <= tolerance
def labelled(chart, values, which):
    nums = [v for v, _, _ in chart.numeric_labels()]
    assert min(nums) <= min(values) and max(nums) >= max(values), (which, nums, values)

s = Session()
try:
    # Scatter and line plots: one mark per pair, on the axes' own scales, joined in order.
    xs, ys = [1, 2, 3, 4, 5], [2, 4, 5, 4, 5]
    for op in ('ScatterPlot', 'LinePlot'):
        c = chart(s, op, {'n': 1, 'Ynew': columns(ys), 'Xnew': columns(xs)})
        fx, fy = c.axis('x'), c.axis('y'); pts = c.points()
        assert len(pts) == 5 and all(near(px, fx(x)) and near(py, fy(y)) for (px, py), x, y in zip(pts, xs, ys)), (op, pts)
        labelled(c, xs, 'x'); labelled(c, ys, 'y')
        if op == 'LinePlot':
            assert all(c.has_line(fx(xs[i]), fy(ys[i]), fx(xs[i + 1]), fy(ys[i + 1])) for i in range(4)), c.lines()
    print('PASS: scatter and line plots place every point on the axes\' scales, joined in order')

    # Bars: one per value, from the baseline to the value; frequencies counted from categories.
    c = chart(s, 'BarPlot', {'values': columns([3, 5, 2]), 'labels': {'columns': [{'title': 'labels', 'values': ['a', 'b', 'c']}], 'source': 't'}})
    fy = c.axis('y'); bars = sorted(c.rects())
    assert len(bars) == 3 and all(near(y, fy(v)) and near(y + h, fy(0)) for (x, y, w, h), v in zip(bars, [3, 5, 2])), bars
    assert all(any(t == label for t, _, _ in c.labels) for label in 'abc'), c.labels
    c = chart(s, 'BarPlotFrequency', {'rawValues': {'columns': [{'title': 'group', 'values': ['a', 'b', 'b', 'c', 'c', 'c']}], 'source': 't'}})
    fy = c.axis('y'); bars = sorted(c.rects())
    assert len(bars) == 3 and all(near(y, fy(count)) and near(y + h, fy(0)) for (x, y, w, h), count in zip(bars, [1, 2, 3])), bars
    print('PASS: bar charts rise from the baseline to each value; frequency bars count each category')

    # Histogram: equal-width bins covering the data, heights that count every observation.
    data = [1, 2, 2, 3, 3, 3, 4, 4, 5, 9]
    c = chart(s, 'HistogramPlot', {'data': columns(data)})
    fy = c.axis('y'); bins = sorted(c.rects()); counts = [round((fy(0) - y) / (fy(0) - fy(1))) for x, y, w, h in bins]
    mids = sorted(v for v, _ in c.ticks('x'))
    width = mids[1] - mids[0]
    assert len(bins) == len(mids) and sum(counts) == len(data) and counts == [3, 3, 3, 0, 0, 1], (counts, mids)
    assert all(near(m2 - m1, width, 0.02) for m1, m2 in zip(mids, mids[1:])) and mids[0] - width / 2 <= min(data) + 0.01 and mids[-1] + width / 2 >= max(data) - 0.01, mids
    assert all(near(w, bins[0][2], 0.1) for _, _, w, _ in bins), bins
    print('PASS: histogram bins are equal, cover the data and count every observation')

    # Box and whisker: quartile box, median marker, whiskers to the data, outliers as points.
    a, b = [1, 2, 3, 4, 5, 6, 7, 8, 20], [2, 3, 4, 5, 6]
    c = chart(s, 'BoxWhiskerPlot', {'data': columns(a, b)})
    fx = c.axis('x'); boxes = sorted(c.rects(), key=lambda r: r[1])
    assert len(boxes) == 2, boxes
    (x1, y1, w1, h1), (x2, y2, w2, h2) = boxes
    assert near(x1, fx(2.5)) and near(x1 + w1, fx(7.5)) and near(x2, fx(2.5)) and near(x2 + w2, fx(5.5)), boxes
    medians = sorted((min(float(p.split(',')[0]) for p in el.get('points').split()) + max(float(p.split(',')[0]) for p in el.get('points').split())) / 2 + dx for el, dx, dy in c.marks('polygon'))
    assert len(medians) == 2 and near(medians[0], fx(4.0)) and near(medians[1], fx(5.0)), medians
    outliers = c.points(); assert len(outliers) == 1 and near(outliers[0][0], fx(20)), outliers
    row = y1 + h1 / 2
    assert any(near(ly, row) and near(ly2, row) and near(min(lx, lx2), fx(1)) for lx, ly, lx2, ly2 in c.lines()) and any(near(ly, row) and near(ly2, row) and near(max(lx, lx2), fx(8)) for lx, ly, lx2, ly2 in c.lines()), c.lines()
    print('PASS: box and whisker plots draw the quartile box, the median, whiskers to the data and the outlier')

    # Normal scores plot: one point per value, rising with the sorted data.
    values = [1, 2, 3, 4, 5, 6, 7, 8]
    c = chart(s, 'NormalPlot', {'X': columns(values)})
    pts = sorted(c.points()); assert len(pts) == 8 and all(pts[i][1] >= pts[i + 1][1] for i in range(7)), pts
    fy = c.axis('y'); assert all(near(py, fy(v)) for (px, py), v in zip(pts, values)), pts
    print('PASS: the normal scores plot places each value in rank order on the value axis')

    # Error bars: a point per pair with a vertical bar from the lower to the upper limit.
    c = chart(s, 'ErrorPlot', {'group-count': 1, 'ydatNew': columns([2, 4, 6]), 'xdatNew': columns([1, 2, 3]), 'ydatuNew': columns([3, 5, 7]), 'ydatlNew': columns([1, 3, 5])})
    fx, fy = c.axis('x'), c.axis('y'); pts = sorted(c.points())
    assert len(pts) == 3 and all(near(px, fx(x)) and near(py, fy(y)) for (px, py), x, y in zip(pts, [1, 2, 3], [2, 4, 6])), pts
    assert all(c.has_line(fx(x), fy(y - 1), fx(x), fy(y + 1)) for x, y in zip([1, 2, 3], [2, 4, 6])), c.lines()
    print('PASS: error bar plots draw each point with its bar from the lower to the upper limit')

    # Spread and ladder plots: every value on the value axis; ladder rungs join each pair.
    c = chart(s, 'SpreadPlot', {'data': columns([1, 2, 3, 4, 5, 6])})
    fx = c.axis('x'); xs_ = sorted(px for px, _ in c.points())   # values run along the horizontal axis
    assert len(xs_) == 6 and all(near(px, fx(v)) for px, v in zip(xs_, [1, 2, 3, 4, 5, 6])), xs_
    c = chart(s, 'LadderPlot', {'data': columns([1, 2, 3], [2, 3, 5])})
    fy = c.axis('y'); left = sorted(c.points()); right = sorted((x + w / 2, y + h / 2) for x, y, w, h in c.rects())   # circles for the first column, squares for the second
    assert len(left) == 3 and len(right) == 3, (left, right)
    assert all(near(py, fy(v)) for (px, py), v in zip(left, [3, 2, 1])) and all(near(py, fy(v)) for (px, py), v in zip(right, [5, 3, 2])), (left, right)
    assert all(c.has_line(left[0][0], fy(a_), right[0][0], fy(b_)) for a_, b_ in [(1, 2), (2, 3), (3, 5)]), c.lines()
    print('PASS: spread and ladder plots place every value on the value axis and join each ladder pair')

    # Control chart: the mean and the three sigma limits where the data put them, the series joined in order.
    y, x = [5, 6, 7, 6, 5, 8], [1, 2, 3, 4, 5, 6]
    c = chart(s, 'ControlPlot', {'Y': columns(y), 'X': columns(x)})
    from datetime import datetime, timedelta
    dates = [(datetime(2026,1,1)+timedelta(days=i)).isoformat() for i in range(6)]
    dated = chart(s, 'ControlPlot', {'Y': columns(y), 'X': columns(dates)})
    serial = chart(s, 'ControlPlot', {'Y': columns(y), 'X': columns([46023+i for i in range(6)])})
    assert dated.points() == serial.points() and dated.lines() == serial.lines()
    print('PASS: imported ISO dates in the control-chart sequence match Excel date serials')
    fx, fy = c.axis('x'), c.axis('y'); mean = sum(y) / 6; sd = (sum((v - mean) ** 2 for v in y) / 5) ** 0.5
    assert '6.167 (mean)' in c.text and all(f'{round(mean + k * sd, 3):g}' in c.text or f'{mean + k * sd:.3f}' in c.text for k in (1, 2, 3, -1, -2, -3)), c.text
    horizontals = [(a, b, cc, d) for a, b, cc, d in c.lines() if near(b, d, 0.01) and abs(cc - a) > c.width / 2]
    assert any(near(b, fy(mean)) for a, b, cc, d in horizontals) and all(any(near(b, fy(mean + k * sd), 2) for a, b, cc, d in horizontals) for k in (3, -3)), horizontals
    assert all(c.has_line(fx(x[i]), fy(y[i]), fx(x[i + 1]), fy(y[i + 1])) for i in range(5)), c.lines()
    print('PASS: the control chart draws the mean and sigma limits where the data put them, with the series joined in order')

    # Forest plot: a point at each estimate, a line across its interval, the figures labelled.
    odds, lci, uci = [1.5, 0.8, 1.2], [1.0, 0.5, 0.9], [2.2, 1.3, 1.6]
    c = chart(s, 'CochranePlot', {'odds': columns(odds), 'lci': columns(lci), 'uci': columns(uci), 'gn': {'skip': True}, 'pg': {'skip': True}})
    fx = c.axis('x'); pts = sorted(c.points(), key=lambda p: p[1])
    assert len(pts) == 3 and all(near(px, fx(o)) for (px, py), o in zip(pts, odds)), pts
    assert all(any(near(b, py) and near(d, py) and near(min(a, cc), fx(l)) and near(max(a, cc), fx(u)) for a, b, cc, d in c.lines()) for (px, py), l, u in zip(pts, lci, uci)), c.lines()
    assert all(f'{o:.2f} ({l:.2f}, {u:.2f})' in c.text for o, l, u in zip(odds, lci, uci)), c.text
    print('PASS: the forest plot draws each estimate with its interval and labels the figures')

    # Population pyramid: bars left and right of the centre, proportional to the numbers, to a stated scale.
    male, female = [10, 20, 30], [12, 22, 32]
    c = chart(s, 'PyramidPlot', {'male': columns(male), 'female': columns(female), 'labels': {'skip': True}})
    assert 'Scale maximum = 32' in c.text, c.text
    centre = next(a for a, b, cc, d in c.lines() if near(a, cc, 0.01))   # the vertical centre line
    lefts = sorted((r for r in c.rects() if near(r[0] + r[2], centre)), key=lambda r: r[1]); rights = sorted((r for r in c.rects() if near(r[0], centre)), key=lambda r: r[1])
    assert len(lefts) == 3 and len(rights) == 3, c.rects()
    unit = rights[2][2] / 32
    assert all(near(r[2], v * unit, 1) for r, v in zip(lefts, male)) and all(near(r[2], v * unit, 1) for r, v in zip(rights, female)), (lefts, rights)
    print('PASS: the population pyramid draws each age group proportionally either side of the centre')

    # ROC: the curve within the unit square, the diagonal drawn, the area the report states.
    c = chart(s, 'ROCPlot', {'series-count': 1, 'P1': columns([1, 2, 3, 4, 5]), 'A1': columns([3, 4, 5, 6, 7])})
    fx, fy = c.axis('x'), c.axis('y')
    curve = sorted({(round((px - fx(0)) / (fx(1) - fx(0)), 4), round((py - fy(0)) / (fy(1) - fy(0)), 4)) for px, py in c.points() if px >= fx(0) - 1})
    assert curve and all(-0.001 <= u <= 1.001 and -0.001 <= v <= 1.001 for u, v in curve), curve
    assert c.has_line(fx(0), fy(0), fx(1), fy(1)), c.lines()
    area = sum((u2 - u1) * (v1 + v2) / 2 for (u1, v1), (u2, v2) in zip(curve, curve[1:]))
    stated = float(re.search(r'extended trapezoidal rule = ([\d.]+)', c.text).group(1))
    assert near(area, stated, 0.011), (area, stated, curve)
    print('PASS: the ROC plot stays in the unit square, draws the diagonal, and its area is the one the report states')

    # Survival plot: steps from each time at the stated proportion.
    times, surv = [1, 2, 3, 4], [0.75, 0.5, 0.5, 0.25]
    c = chart(s, 'SurvivalPlot', {'group-count': 1, 'xdatNew': columns(times), 'cdatNew': columns([1, 1, 0, 1]), 'ydatNew': columns(surv), 'ydatlNew': {'skip': True}, 'ydatuNew': {'skip': True}})
    fx, fy = c.axis('x'), c.axis('y'); pts = sorted(c.points()); events = [(t, p) for t, p, e in zip(times, surv, [1, 1, 0, 1]) if e]
    assert len(pts) == 3 and all(any(near(px, fx(t)) and near(py, fy(p)) for px, py in pts) for t, p in events), pts   # a marker at each event, not at the censoring
    # One horizontal segment per interval at the proportion reached, including through the censored time, and a drop at each event.
    assert all(c.has_line(fx(times[i]), fy(surv[i]), fx(times[i + 1]), fy(surv[i])) for i in range(3)), c.lines()
    assert all(c.has_line(fx(times[i + 1]), fy(surv[i]), fx(times[i + 1]), fy(surv[i + 1])) for i in range(3) if surv[i] != surv[i + 1]), c.lines()
    print('PASS: the survival plot marks each event and steps on at the stated proportion through censoring')
finally:
    s.finish()
