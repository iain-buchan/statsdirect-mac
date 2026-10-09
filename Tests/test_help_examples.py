"""Replay of the help's worked examples through the Mac engine host: each page that uses the test
workbook is run with the columns it names, prompts answered as the page says or by their defaults,
and every figure the page prints is looked for in the Mac report. Writes Tests/help-examples-results.md."""
import html, re, sys, uuid
from pathlib import Path
import openpyxl
from help_examples import examples, ROOT, NUMBER, QUOTED, quoted_spans
ARGS = sys.argv[1:]; sys.argv = sys.argv[:1]   # the engine driver reads its own arguments
from test_menu import Session

wb = openpyxl.load_workbook(ROOT / 'FullEngine/Upstream/StatsDirectUI/Assets/Data/test.xlsx', read_only=True, data_only=True)
COLUMNS = {}   # lower-case title -> every column of that title, one per worksheet
for ws in wb.worksheets:
    rows = list(ws.iter_rows(values_only=True))
    if not rows: continue
    for c, title in enumerate(rows[0]):
        if title is None: continue
        values = [row[c] if c < len(row) else None for row in rows[1:]]
        if None in values: values = values[:values.index(None)]   # a column's example ends at its first blank cell
        COLUMNS.setdefault(str(title).strip().lower(), []).append({'title': str(title).strip(), 'values': [('' if v is None else v.isoformat() if hasattr(v, 'isoformat') else v) for v in values], 'sheet': ws.title})

def candidates(name):
    """The workbook columns a page's name may mean: an exact title, else the one title containing the name (the shortest) or starting it."""
    key = name.strip().lower()
    if key in COLUMNS: return COLUMNS[key]
    if len(key) < 4: return []
    near = sorted((k for k in COLUMNS if key in k or (len(k) >= 6 and key.startswith(k))), key=len)   # 'Hypertensives' names the column 'Hypertensive'
    return COLUMNS[near[0]] if near else []
def column(name, sheet=None, length=None):
    """The column a page's name means: in the worksheet the page's columns share, and, where a title recurs
    there (one worksheet holds several examples), the one whose rows match the page's other columns."""
    found = candidates(name)
    if sheet: found = [c for c in found if c['sheet'] == sheet] or found
    if length is not None: found = [c for c in found if len(c['values']) == length] or found
    return found[0] if found else None
def common_length(names, sheet):
    tally = {}
    for n in names:
        for c in candidates(n):
            if sheet is None or c['sheet'] == sheet: tally[len(c['values'])] = tally.get(len(c['values']), 0) + 1
    return max(tally, key=tally.get) if tally else None
def columns_sheet(names):
    """The worksheet holding most of the named columns, since many titles recur across worksheets."""
    tally = {}
    for n in names:
        for c in candidates(n): tally[c['sheet']] = tally.get(c['sheet'], 0) + 1
    return max(tally, key=tally.get) if tally else None

def frame_answer(cols):
    return {'source': 'test.xlsx', 'columns': [{'title': c['title'], 'values': [('*' if v == '' else v) for v in c['values']]} for c in cols]}

def report_numbers(html_text):
    text = html.unescape(re.sub(r'<[A-Za-z/!][^>]*>', ' ', html_text))   # tags only: a bare "<" in "P < 0.0001" is text
    return NUMBER.findall(text)

STOP = {'the', 'a', 'an', 'of', 'for', 'and', 'or', 'data', 'select', 'column', 'columns', 'marked', 'when', 'asked', 'prompted', 'enter', 'to', 'in', 'as', 'at', 'with', 'if', 'skip', 'none',
        'not', 'you', 'are', 'want', 'whether', 'then', 'this', 'that', 'from', 'click', 'button', 'box', 'option', 'also', 'each', 'all', 'any', 'your', 'will', 'have', 'has', 'been', 'one', 'first', 'next', 'other'}
def stem(w): return re.sub(r'(ies|es|s|ed|ing)$', '', w) if len(w) > 4 else w
def words(text): return {stem(w) for w in re.findall(r'[a-z]+', text.lower()) if w not in STOP and len(w) > 2}
def roles(example):
    """The words a page attaches to each quoted column ('"Time Surv" when asked for times'), for matching prompts."""
    text = example['instructions']; out = []
    for start, end, _ in quoted_spans(text):
        after = text[end:end + 90]; before = text[max(0, start - 90):start]
        role = re.search(r'(?:when (?:asked|prompted) for|for)\s+(?:the\s+)?([^.,;"\u201c\u201d]{1,50})', after)
        context = role.group(1) if role else ''
        mb = re.search(r'([^.,;"\u201c\u201d]{1,50})\s*$', before)
        out.append(words(context) | (words(mb.group(1)) if mb and not role else set()))
    return out
def overlap(a, b):
    """Words shared by two sets, a word counting when one is the other's stem or prefix (censor, censorship)."""
    return {x for x in a if any(x == y or (len(x) >= 4 and len(y) >= 4 and (x.startswith(y) or y.startswith(x))) for y in b)}
def pick(pending, prompt_text, take):
    """The pending columns whose role words fit the prompt best, else the first ones."""
    pw = words(prompt_text)
    scored = sorted(range(len(pending)), key=lambda i: (-len(overlap(pending[i][1], pw)), i))
    chosen = scored[:take] if overlap(pending[scored[0]][1], pw) else list(range(take))
    chosen.sort(); return [pending[i] for i in chosen], [c for i, c in enumerate(pending) if i not in chosen]

def matches(expected, found, relative_tolerance=0):
    """How many of the page's figures appear in the report, exactly or at the page's printed precision."""
    pool = {}
    for f in found:
        try: pool.setdefault(float(f), []).append(f)
        except ValueError: pass
    missing = []
    for e in expected:
        try: value = float(e)
        except ValueError: continue
        decimals = len(e.split('.')[1]) if '.' in e and 'e' not in e.lower() else 0
        if e in found or any(abs(v - value) <= max(0.5 * 10 ** -decimals + 1e-12, abs(value)*relative_tolerance) for v in pool): continue
        missing.append(e)
    return missing

WORD_NUMBERS = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10}
def prompt_words(p): return words((p.get('prompt') or p.get('title') or '') + ' ' + (p.get('name') or '').replace('-', ' '))   # the operation's title would match too much
def sentences(text): return [t.strip() for t in re.split(r'(?<=[.;])\s+', text) if t.strip()]
def clauses(text):
    """Sentences split again at 'and' and commas, so one instruction is read for one prompt."""
    return [c.strip() for t in sentences(text) for c in re.split(r',| and |; ', t) if c.strip()]
def said_blank(example, p):
    keys = prompt_words(p)
    return any(len(keys & words(c)) >= 2 and re.search(r'\bleave\b.*\bblank\b', c, re.I) for c in clauses(example['instructions']))
def said_number(example, p):
    """A number the page tells the user to enter for this prompt ('enter the population mean as 120',
    'Choose 90% as the confidence level'): the number nearest the prompt's own words."""
    keys = prompt_words(p); best = None
    for clause in clauses(example['instructions']):
        overlap = keys & words(clause)
        if not overlap or not re.search(r'\b(enter|as|choose|number of)\b', clause, re.I): continue
        for m in re.finditer(r'(?<![\w.])(\d+(?:\.\d+)?)%?|\b(one|two|three|four|five|six|seven|eight|nine|ten)\b', clause, re.I):
            value = float(m.group(1)) if m.group(1) else WORD_NUMBERS[m.group(2).lower()]
            distance = min(abs(m.start() - clause.lower().find(w)) for w in overlap)
            if best is None or (len(overlap), -distance) > best[0]: best = ((len(overlap), -distance), value)
    return best[1] if best else None
def said_boolean(example, p):
    """Checked or unchecked, yes or no, when the page mentions the option."""
    keys = prompt_words(p)
    for clause in clauses(example['instructions']):
        if not (keys & words(clause)): continue
        low = clause.lower()
        if re.search(r'\b(unchecked|unticked|not checked|not ticked|is not checked|click on "?no|click no|answer no|leave .* unchecked)\b', low): return False
        if re.search(r'\b(checked|ticked|tick the|check the|click on "?yes|click yes|answer yes)\b', low): return True
    return None
def said_skip(example, p):
    keys = prompt_words(p)
    return any((keys & words(c)) and re.search(r'\b(cancel|skip|click on "?no)\b', c, re.I) for c in clauses(example['instructions']))
def said_option(example, p):
    for sentence in sentences(example['instructions']):
        if 'option' not in sentence.lower(): continue
        for o in p.get('options', []):
            if words(str(o.get('label', '')) + ' ' + str(o.get('value', ''))) & words(sentence): return o['value']
    return None
def expand_columns(example):
    """The columns a page names, from the worksheet most of them share, with '"P1L1" etc.' expanded to every title of that pattern."""
    out = []
    text = example['instructions']; sheet = columns_sheet(example['columns']); length = common_length(example['columns'], sheet)
    for name, role in zip(example['columns'], roles(example)):
        after = text[text.find(name) + len(name):text.find(name) + len(name) + 40] if name in text else ''
        if re.search(r'\d', name) and (re.search(r'\betc\b', after) or 'Repeat this selection' in text):
            pattern = '^' + re.sub(r'\d+', r'\\d+', re.escape(name)) + '$'
            found = [c for k, cols in COLUMNS.items() for c in cols if re.match(pattern, c['title'], re.I) and (sheet is None or c['sheet'] == sheet)]
            out.extend((c, role) for c in found)
        else:
            c = column(name, sheet, length)
            if c: out.append((c, role or words(c['title'])))   # with no stated role, the title's own words say which prompt it fits
    return out

# Pages whose instructions the harness cannot read: the columns they mean, and prompt answers they state.
OVERRIDES = {
    'randomization/preference_group.htm': {'columns': ['Group capacity', '1st choice', '2nd choice', '3rd choice'], 'answers': {'seed': 10}},
    'nonparametric_methods/diversity.htm': {'answers': {'boots': 2000, 'seed': 1}},
    'nonparametric_methods/gini.htm': {'answers': {'boots': 2000, 'seed': 2001}},
    'nonparametric_methods/quantile_ci.htm': {'answers': {'gamma':90,'quantile':0.75,'conservative-ci':False}},
    'nonparametric_methods/quantile_ci.htm#conservative': {'answers': {'gamma':90,'quantile':0.75,'conservative-ci':True}},
    'nonparametric_methods/loess.htm': {'answers': {'plotFitsAndCi': True}},   # the page says to check the box for the plot
}

def documented_inputs(page, session=None):
    """Explicit selections where the prose includes multiple datasets, preprocessing or
    successive groups. Names are taken from the shipped workbook, not fuzzy matching."""
    def frame(sheet, *names, rows=None):
        result = []
        for name in names:
            c = column(name, sheet)
            assert c and c['sheet'] == sheet and c['title'].lower() == name.lower(), (sheet, name)
            result.append(dict(c, values=c['values'][:rows] if rows else c['values']))
        return frame_answer(result)
    if page == 'analysis_of_variance/latin_square.htm':
        return {k: frame('ANOVA', v) for k,v in [('observations','Observations'),('column','Rabbit'),('row','Position'),('treatment','Order')]}
    if page == 'analysis_of_variance/crossover.htm':
        return {'_grids': [frame('ANOVA','Drug 1'),frame('ANOVA','Placebo 1'),{'skip':True},frame('ANOVA','Drug 2'),frame('ANOVA','Placebo 2'),{'skip':True}]}
    if page == 'analysis_of_variance/nested.htm':
        return {'Number of groups': {'n':4}, **{f'Group {g}: one column per subgroup':frame('ANOVA',*[f'P{g}L{l}' for l in range(1,4)]) for g in range(1,5)}}
    if page == 'regression_and_correlation/grouped_covariance.htm':
        return {'Select predictor (X) series — one column per group':frame('Regression','Log Dose_Std','Log Dose_I','Log Dose_F'), 'Use Y replicates':True, 'Confidence level':{'ci':95},
            **{f'Group {i}: one column of Y replicates for each X value':frame('Regression',*[f'BD {j}_{suffix}' for j in range(1,n+1)]) for i,suffix,n in [(1,'Std',3),(2,'I',5),(3,'F',3)]}}
    if page == 'regression_and_correlation/conditional_logistic.htm':
        # The dummy column extends beyond this example. Select the same 112 rows
        # as PAIRID and LBWT, as a user selects a rectangle in the worksheet.
        return {'stratum':frame('Regression','PAIRID'),'case-control':frame('Regression','LBWT'),
            'predictors':frame('Regression','RACE (b)','SMOKE','HT','UI','PTD','LWT',rows=112),'accuracy':'0.000000000001'}
    if page == 'regression_and_correlation/poisson.htm':
        names=['Veterans']+[f'Age group ({age})' for age in ['25-29','30-34','35-39','40-44','45-49','50-54','55-59','60-64','65-69','70+']]
        return {'grouping':'individual','intercept':True,'has-exposure':'true','response':frame('Regression','Cancers'),
            'exposure':frame('Regression','Subject-years'),'predictors':frame('Regression',*names)}
    if page == 'survival_analysis/wei_lachin.htm':
        return {'gid':frame('Survival','Treatment Gp'),'nr':4, **{f'Select data for {role} (repeat {i})':frame('Survival',f'{col} m{i}') for i in range(1,5) for role,col in [('TIMES','time'),('CENSORSHIP','censor')]}}
    if page == 'graphics/control.htm':
        return {'Y':frame('Graphics','Process'),'X':frame('Graphics','Date')}
    if page == 'survival_analysis/logrank.htm#stratified':
        return {'gid':frame('Survival','Group'),'times':frame('Survival','Trial Time'),
                'deaths':frame('Survival','Censorship',rows=25),'strata':frame('Survival','Strat')}
    if page == 'nonparametric_methods/friedman.htm#cochran':
        # The separate 12-game sportsmen table printed on the page, not the grass workbook example.
        rows=[[1,1,1],[1,1,1],[0,1,0],[1,1,0],[0,0,0],[1,1,1],
              [1,1,1],[1,1,0],[0,0,1],[0,1,0],[1,1,1],[1,1,1]]
        return {'data':{'columns':[{'title':f'Sportsman {c+1}','values':[r[c] for r in rows]} for c in range(3)]}}
    if page == 'parametric_methods/z_normal.htm#2':
        values=column('Michelson','Parametric')['values']
        return {'data':{'columns':[{'title':'First 50','values':values[:50]},{'title':'Last 50','values':values[50:]}]}}
    if page == 'graphics/survival.htm':
        km=session.run('KaplanMeier', {'groups':frame('Survival','Group Surv'), 'times':frame('Survival','Time Surv'),
                                     'deaths':frame('Survival','Censor Surv'),'save':True})
        output=km['frames'][0]; inputs=[]
        for group in range(2):
            length=max(c['row'] for c in output['cells'] if c['col']==10*group)
            for offset in [0,1,2,4,5]:
                cells={c['row']:c['text'] for c in output['cells'] if c['col']==10*group+offset}
                inputs.append({'columns':[{'title':cells[0],'values':[cells.get(r,'*') for r in range(1,length+1)]}]})
        return {'group-count':2,'_grids':inputs}
    return {}

# These sentences interpret results or describe a different estimator; they are
# not report output. Keep the output checks strict (including negative signs).
OUTPUT_END = {
    'analysis_of_variance/nested.htm': 'The "F (VR between groups)" statistic',
    'nonparametric_methods/gini.htm': 'The bias, standard error and confidence limits',
    'parametric_methods/reference_range.htm': 'These data are not from a normal distribution',
    'parametric_methods/z_normal.htm': 'The measurements were on average',
    'meta_analysis/risk_difference.htm': 'Here we can say with 95% confidence',
    'regression_and_correlation/simple_linear.htm': 'From this analysis we have gained',
}
def run_example(s, example, operation, booleans=False, strategy='role', choice=0):
    explicit = documented_inputs(example['page'], s)
    end = OUTPUT_END.get(example['page'])
    if end:
        expected = example['expected'].split(end)[0]
        example = dict(example, expected=expected, numbers=NUMBER.findall(expected))
    override = OVERRIDES.get(example['page'], {})
    if override.get('columns'): example = dict(example, columns=override['columns'], instructions=example['instructions'] + ' ' + ' '.join(f'"{c}"' for c in override['columns']))
    named = expand_columns(example)
    if not named and not explicit: return {'status': 'no columns', 'detail': 'none of the quoted names is a column of the test workbook'}
    if operation == 'MethodComparisonRegression': return {'status': 'deferred', 'detail': 'R-based menu host is not enabled; use an R session.'}
    id, st = s.start(operation); prompts = []; pending = list(named); groupwise = len(named) > len(example['columns'])
    try:
        for _ in range(60):
            if st.get('state') != 'input': break
            p = st['prompt']; prompts.append(p.get('name') or p.get('prompt'))
            if p.get('error'): return {'status': 'refused', 'detail': f"{p.get('name') or p.get('prompt')}: {p['error']}", 'prompts': prompts}
            text = p.get('prompt') or p.get('title') or ''
            if p.get('name') in explicit: value = explicit[p['name']]
            elif text in explicit: value = explicit[text]
            elif p['kind'] == 'grid' and '_grids' in explicit: value = explicit['_grids'].pop(0)
            elif p.get('name') in override.get('answers', {}): value = override['answers'][p['name']]
            elif p['kind'] == 'grid' and p.get('initial'): value = p['initial']
            elif p['kind'] == 'grid':
                group = re.match(r'(Group|Repeat) (\d+):', text)
                if groupwise and group:
                    # A two-dimensional frame from '"P1L1" etc.': the digit slot that counts the groups picks each group's columns.
                    k = int(group.group(2)); titles = [c['title'] for c, _ in pending]
                    slots = [sorted({re.findall(r'\d+', t)[i] for t in titles}) for i in range(len(re.findall(r'\d+', titles[0])))]
                    before = [titles[0][:m.start()].lower() for m in re.finditer(r'\d+', titles[0])]   # the text before each digit slot
                    slot = next((i for i, b in enumerate(before) if group.group(1) == 'Repeat' and 'rep' in b), None)
                    if slot is None: slot = next((i for i, vals in enumerate(slots) if len(vals) == groups), 0) if (groups := len(slots) and max(len(v) for v in slots)) else 0
                    chosen = [(c, r) for c, r in pending if int(re.findall(r'\d+', c['title'])[slot]) == k]
                    if not chosen: return {'status': 'too few columns', 'detail': f"{text} has no columns of the pattern", 'prompts': prompts}
                    pending = [x for x in pending if x not in chosen]; value = frame_answer([c for c, _ in chosen])
                elif p.get('skip') and said_skip(example, p): value = {'skip': True}
                else:
                    take = max(p.get('minColumns', 1), min(p.get('maxColumns', 1), len(pending)))
                    if len(pending) < max(1, p.get('minColumns', 1)):
                        if p.get('skip'): value = {'skip': True}   # an optional frame the page does not mention
                        else: return {'status': 'too few columns', 'detail': f"{text} needs {p.get('minColumns')} column(s); {len(pending)} left", 'prompts': prompts}
                    elif strategy == 'role': chosen, pending = pick(pending, text, take); value = frame_answer([c for c, _ in chosen])
                    else: value = frame_answer([c for c, _ in pending[:take]]); pending = pending[take:]
            elif p['kind'] == 'options': value = {o['value']: o['selected'] for o in p['options']}
            elif p['kind'] in ('fields', 'settings'):
                value = {o['name']: o['defaultValue'] for o in p['fields']}
                said = said_number(example, p)
                if said is not None and len(p['fields']) == 1: value = {p['fields'][0]['name']: said}
            elif p['kind'] == 'boolean': value = said_boolean(example, p) if said_boolean(example, p) is not None else booleans
            elif p['kind'] == 'confidence':
                said = said_number(example, p)
                if said is None:   # 'Choose 90% as the confidence level', even when the prompt only says 'Enter a value'
                    m = next((re.search(r'(\d+(?:\.\d+)?)\s*%', c) for c in clauses(example['instructions']) if 'confidence' in c.lower() and re.search(r'\d+(?:\.\d+)?\s*%', c)), None)
                    said = float(m.group(1)) if m else None
                value = said if said is not None else p['defaultValue']
            elif p['kind'] in ('number', 'integer') and said_blank(example, p) and p.get('skip'): value = {'skip': True}
            elif p['kind'] in ('number', 'integer') and said_blank(example, p): value = ''
            elif p['kind'] in ('number', 'integer') and said_number(example, p) is not None: value = said_number(example, p)
            elif p['kind'] == 'option' and said_option(example, p) is not None: value = said_option(example, p)
            elif p['kind'] == 'option' and choice: value = p['options'][min(choice, len(p['options']) - 1)]['value']; choice = 0   # a variant of the first option prompt
            elif p.get('defaultValue') is not None: value = p['defaultValue']
            elif p['kind'] == 'option': value = p['options'][0]['value']
            elif p['kind'] == 'selectList': value = [p['options'][0]['value']] if p.get('multiple') else p['options'][0]['value']
            elif p.get('skip'): value = {'skip': True}
            else: return {'status': 'unanswered', 'detail': f"{p['kind']} {p.get('name') or p.get('prompt')}", 'prompts': prompts}
            s.request(action='answer', id=id, token=st['token'], value=value); st = s.wait(id)
        if st.get('state') != 'complete': return {'status': 'failed', 'detail': str(st.get('error'))[:200], 'prompts': prompts}
        if example['page'].startswith('graphics/'):
            if operation.endswith('Text'):
                assert '<pre>' in st.get('html','') and len(st['html']) > 200, st.get('html')
                return {'status': 'chart drawn', 'detail': 'Text chart generated', 'prompts': prompts, 'missing': [], 'total': 0}
            assert '<svg' in st.get('html','') and 'Chart not drawn' not in st['html'], st.get('html')
            return {'status': 'chart drawn', 'detail': 'SVG generated; geometry checked separately in test_charts.py', 'prompts': prompts, 'missing': [], 'total': 0}
        found = report_numbers(st.get('html') or '')
        # Follow-ons the page runs from the Further analysis box (named, or any when the page says 'multiple comparisons').
        for su in st.get('suggestions') or []:
            title = su.get('title') or ''
            mentioned = example['instructions'] + ' ' + example['expected']; low = mentioned.lower(); tl = title.lower()
            wanted = title in mentioned or ('comparison' in tl and 'comparison' in low) or ('variance' in tl and 'equality' not in tl and 'analysis of variance' in low) \
                or ('area' in tl and 'area under' in low) or ('hazard' in tl and 'hazard ratio' in low) or ('model analysis' in tl and 'model analysis' in low) or len(words(title) & words(example['expected'])) >= 3
            if wanted:
                fid = str(uuid.uuid4()); fs = s.request(action='start', id=fid, operation=su['operation'], parent=id)
                if fs.get('error'): continue
                fst = s.wait(fid); n = 0
                while fst.get('state') == 'input' and n < 20:
                    fp = fst['prompt']; n += 1
                    if fp.get('error'): break
                    if fp['kind'] == 'options': fv = {o['value']: o['selected'] for o in fp['options']}
                    elif fp['kind'] in ('fields', 'settings'): fv = {o['name']: o['defaultValue'] for o in fp['fields']}
                    elif fp['kind'] == 'boolean': fv = booleans
                    elif fp.get('defaultValue') is not None: fv = fp['defaultValue']
                    elif fp['kind'] == 'option': fv = fp['options'][0]['value']
                    elif fp['kind'] == 'selectList': fv = [o['value'] for o in fp['options']] if fp.get('multiple') else fp['options'][0]['value']
                    elif fp.get('skip'): fv = {'skip': True}
                    else: break
                    s.request(action='answer', id=fid, token=fst['token'], value=fv); fst = s.wait(fid)
                if fst.get('state') == 'complete': found += report_numbers(fst.get('html') or ''); prompts.append('+' + su['operation'])
                else: s.request(action='cancel', id=fid); s.wait(fid)
                s.request(action='release', id=fid)
        # Figures with decimals are the statistics; integers are mostly the example data echoed on the page.
        figures = [e for e in example['numbers'] if '.' in e]
        # The help explicitly notes iterative stopping affects the last place of
        # the widest conditional-logistic odds-ratio limits. R 4.6.1 confirms this;
        # allow 1e-7 relative error here only, never ignore a sign or decimal suffix.
        tolerance = 1e-7 if example['page']=='regression_and_correlation/conditional_logistic.htm' else 0
        missing = matches(figures, found, tolerance)
        random = bool(re.search(r'bootstrap|monte carlo|simulat', example['expected'], re.I))
        status = 'matched' if not missing else 'differs (random method)' if random else 'differs'
        return {'status': status, 'detail': f"{len(figures) - len(missing)}/{len(figures)} figures found" + (' (1e-7 relative tolerance for iterative estimates)' if tolerance else '') + (f"; missing {', '.join(missing[:8])}" if missing else ''), 'prompts': prompts, 'missing': missing, 'total': len(figures), 'found': found, 'figures': figures}
    finally:
        s.close(id)

# Pages whose figures the Mac engine reproduces, with the operation and the answer to yes/no prompts that
# does it. `python3 Tests/test_help_examples.py` checks these (test.sh); `--report` surveys every page
# and rewrites Tests/help-examples-results.md.
BASELINE = [
    ('nonparametric_methods/loess.htm', 'LOESS', False),
    ('nonparametric_methods/quantile_ci.htm', 'Quantile', False),
    ('nonparametric_methods/quantile_ci.htm#conservative', 'Quantile', True),
    ('analysis_of_variance/crossover.htm', 'Crossover', False),
    ('analysis_of_variance/latin_square.htm', 'LatinSquare', False),
    ('analysis_of_variance/nested.htm', 'TwoWayNested', False),
    ('nonparametric_methods/cuzick.htm', 'Cuzick', False),
    ('nonparametric_methods/diversity.htm', 'Diversity', False),
    ('nonparametric_methods/gini.htm', 'Gini', False),
    ('nonparametric_methods/friedman.htm', 'Friedman', False),
    ('nonparametric_methods/friedman.htm#cochran', 'CochranQ', False),
    ('nonparametric_methods/nonparametric_regression.htm', 'NonparametricLinearRegression', False),
    ('parametric_methods/reference_range.htm', 'ReferenceRange', False),
    ('parametric_methods/z_normal.htm', 'ZSingle', False),
    ('parametric_methods/z_normal.htm#2', 'ZUnpaired', False),
    ('regression_and_correlation/conditional_logistic.htm', 'ConditionalLogisticRegression', False),
    ('regression_and_correlation/grouped_covariance.htm', 'GroupedCovariance', False),
    ('regression_and_correlation/poisson.htm', 'PoissonRegression', False),
    ('survival_analysis/logrank.htm', 'LogRank', False),
    ('survival_analysis/logrank.htm#stratified', 'LogRank', False),
    ('survival_analysis/wei_lachin.htm', 'WeiLachin', False),
    ('analysis_of_variance/one_way.htm', 'OneWay', False),
    ('analysis_of_variance/two_way.htm', 'TwoWay', False),
    ('analysis_of_variance/two_way_replicate.htm', 'ReplicateTwoWay', False),
    ('meta_analysis/correlation.htm', 'MetaCorrelation', False),
    ('meta_analysis/effect_size.htm', 'Effect', False),
    ('meta_analysis/incidence_rate.htm', 'MetaIncidenceRateDifference', False),
    ('meta_analysis/mh.htm', 'Mantel', False),
    ('meta_analysis/peto.htm', 'PetoMeta', False),
    ('meta_analysis/proportion.htm', 'ProportionMeta', False),
    ('meta_analysis/relative_risk.htm', 'RelativeRiskMeta', False),
    ('meta_analysis/risk_difference.htm', 'RiskDifference', False),
    ('meta_analysis/summary.htm', 'MetaSummary', False),
    ('nonparametric_methods/kendall_correlation.htm', 'Kendall', False),
    ('nonparametric_methods/kruskal_wallis.htm', 'Kruskal', False),
    ('nonparametric_methods/mann_whitney.htm', 'MannWhitney', False),
    ('nonparametric_methods/smirnov.htm', 'Smirnov', False),
    ('nonparametric_methods/spearman.htm', 'Spearman', False),
    ('nonparametric_methods/wilcoxon_signed_ranks.htm', 'Wilcoxon', False),
    ('parametric_methods/f_variance_ratio.htm', 'VarianceRatio', False),
    ('parametric_methods/normality.htm', 'Normality', False),
    ('parametric_methods/paired_t.htm', 'TPaired', False),
    ('parametric_methods/single_sample_t.htm', 'TSingle', False),
    ('parametric_methods/unpaired_t.htm', 'TUnpaired', False),
    ('randomization/preference_group.htm', 'Preferences', False),
    ('regression_and_correlation/grouped_linearity_replicates.htm', 'GroupedLinearity', False),
    ('regression_and_correlation/logistic.htm', 'LogisticRegression', False),
    ('regression_and_correlation/multiple_linear.htm', 'MultipleLinearRegression', False),
    ('regression_and_correlation/polynomial.htm', 'PolynomialRegression', False),
    ('regression_and_correlation/probit_analysis.htm', 'Logit', False),
    ('regression_and_correlation/simple_linear.htm', 'SimpleLinearRegression', False),
    ('survival_analysis/cox_regression.htm', 'CoxRegression', False),
    ('survival_analysis/follow_up_life_table.htm', 'FollowUpLifetable', False),
    ('survival_analysis/kaplan_meier.htm', 'KaplanMeier', False),
]

if __name__ == '__main__':
    report = '--report' in ARGS
    only = next((a for a in ARGS if not a.startswith('--')), None)
    s = Session(); lines = ['| Page | Operation | Result | Detail |', '|---|---|---|---|']; counts = {}
    try:
        if not report:
            failures = []
            for page, op, yes in BASELINE:
                if only and only not in page: continue
                ex = next(e for e in examples() if e['page'] == page)
                r = None
                for strategy in ('role', 'order'):
                    r = run_example(s, ex, op, yes, strategy)
                    if r['status'] == 'matched': break
                if r['status'] != 'matched': failures.append(f"{page} ({op}): {r['status']}: {r['detail'][:160]}")
            assert not failures, '\n'.join(failures)
            print(f'PASS: the Mac engine reproduces the reported statistics of {len(BASELINE)} worked examples in the help, run through the prompt/answer boundary with the test workbook')
        else:
            for ex in examples():
                if only and only not in ex['page']: continue
                if not ex['operations'] or not ex['numbers']: continue
                # Every operation the page documents is tried, with the yes/no prompts answered No and then Yes; the best match counts.
                best = None
                union = {}   # operation -> figures found across its variants, for pages printing several variants of one analysis
                for op in ex['operations']:
                    for booleans, strategy, choice in ((False, 'role', 0), (False, 'order', 0), (True, 'role', 0), (True, 'order', 0), (False, 'role', 1), (False, 'role', 2), (False, 'role', 3)):
                        try: r = run_example(s, ex, op, booleans, strategy, choice)
                        except Exception as e: r = {'status': 'harness error', 'detail': str(e)[:200]}
                        r['operation'] = op; r['booleans'] = booleans
                        if r.get('found'): union.setdefault(op, set()).update(r['found'])
                        rank = (r['status'] in ('matched', 'chart drawn'), r['status'].startswith('differs'), -(len(r.get('missing', [])) if r.get('total') else 10 ** 6))
                        if best is None or rank > best[0]: best = (rank, r)
                        if r['status'] in ('matched', 'chart drawn'): break
                    if best[1]['status'] in ('matched', 'chart drawn'): break
                r = best[1]; op = r['operation']
                if r['status'].startswith('differs') and op in union and not matches(r['figures'], list(union[op])):
                    r = dict(r, status='matched across runs', detail=f"{r['total']}/{r['total']} figures found over the variants the page prints")
                counts[r['status']] = counts.get(r['status'], 0) + 1
                lines.append(f"| {ex['page']} | {op}{' (yes to questions)' if r['booleans'] else ''} | {r['status']} | {r['detail'].replace('|', '/')} |")
                print(f"{r['status']:16s} {ex['page']:55s} {op:32s} {r['detail'][:100]}", flush=True)
            (ROOT / 'Tests/help-examples-results.md').write_text('# Help examples replayed through the Mac engine\n\n'
                'Worked help examples using the test workbook, run through the Mac engine host with the documented columns and answers; '
                'reported statistics are matched at their printed precision, with explanatory prose excluded. Conditional logistic estimates allow 1e-7 relative error for iterative stopping. Plots are checked for generated SVG or text; geometry has separate regression tests. Deferred methods are listed explicitly. '
                'Regenerate with `python3 Tests/test_help_examples.py --report`.\n\n' + '\n'.join(lines) + '\n')
            print(counts)
    finally:
        s.finish()
