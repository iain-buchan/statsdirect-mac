"""A missing subject identifier or category is refused at the picker, through the Mac operation host, as the checks Windows added to
tests/DataSelection/ValidationPolicyChecks.cs at v5.3.9 (f41aad46) have it.

Since 5.3.9 the shared ValidationProcessor's NoMissingData tests a classifier frame as it tests a numeric one, so a blank cell or a typed *
among the subject identifiers of the time series summary (TimeSeriesSummary subjectIds), or among the categories of the contraction of
frequencies (ContractFrequencies categories), is refused with "Data with missing values cannot be used here" before the analysis meets
the missing code. At 5.3.8 those answers were accepted and the analysis then failed with an exception.

Mirrored from Windows, in its order and with its cells, answers and expected values (12 checks):
- each frame "deserializes its category mode and its NoMissingData" (2);
- the cells Subject / p1, p2, blank, p4, p2 ("a blank cell") and p1, *, p3, p4, p2 ("a typed * marker") are refused by NoMissingData with
  exactly that message, and p1, p2, p3, p4, p2 ("every value present") is accepted, at each frame (6);
- through the whole analysis, blank then complete: the time series summary of times 0, 0, 1, 1 ("Time"), observations 1, 2, 3, 4
  ("Level") and subjects p1, p2, blank or p1, p2 ("Subject"), no groups, 95% confidence and no exact P, stops at the message or gives
  the means by time 1.5 and 3.5; the contraction of the categories red, blue, blank or red, blue ("Category") stops at the message or
  gives the labels red, blue with the frequencies 2, 2 (4).

Where the Mac host gives the evidence otherwise:
- Windows reads the deserialized FrameParameter. The Mac host reports the frame's selection mode in the prompt it presents, and not its
  validators: the mode is asserted from the prompt, and the validator from the operation definition the engine under test loads
  (Operations/<operation>.xml beside the library; in the app, in Contents/Resources/Engine). That the validator binds is what the
  refusals show.
- Windows acquires the cells into a ClassifierVariable and counts its length (5) and its missing codes (1 or 0) before validating.
  The Mac host answers the frame's prompt with a worksheet selection as the form sends one (a blank cell as empty text, a typed * as
  itself; FullEngine/HostParameters.cs reads both as the missing code and keeps the row) and applies the same validators, so the
  check is the picker's verdict: refused at that prompt with exactly the message, or accepted. For the time series summary the
  identifiers follow five times and five observations (0, 0, 1, 1, 2 and 1 to 5; Windows validates the frame alone, so they are the
  Mac's), and the host checks the row count against the times before it runs the validators, so the refusal also shows the column was
  held at five rows; accepted means the host goes on to ask for the groups. For the contraction, accepted means the run completes
  and counts all five cells (p1 1, p2 2, p3 1, p4 1).
- The native ParameterBag is not returned. The means by time are read from the report's table of the single group (Windows's *group
  and *time blocks), the contracted labels and frequencies from the first and last columns of the output frame the host returns.
The validation message is compared exactly; no check here is weaker than its Windows original.
"""
import os
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from test_menu import ROOT, Session


ENGINE = Path(os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib')))
NO_MISSING = 'Data with missing values cannot be used here'
CATEGORY = 'CategoryReplaceMissing'
SCHEMA = '{http://www.statsdirect.com/schemas/Operation.xsd}'
PREFS = {'use-default-ci': False}   # the confidence level is asked and answered, as Windows answers ci
WORKBOOK = 'Identifiers.xlsx'       # never opened: the answers carry their cells

# Windows's (operation, frame) pairs and its three selections, each under the title "Subject"
FRAMES = [('TimeSeriesSummary', 'subjectIds'), ('ContractFrequencies', 'categories')]
SELECTIONS = [('a blank cell', ['p1', 'p2', None, 'p4', 'p2']),
              ('a typed * marker', ['p1', '*', 'p3', 'p4', 'p2']),
              ('every value present', ['p1', 'p2', 'p3', 'p4', 'p2'])]

checks = 0
failures = []


def check(ok, what, detail=''):
    global checks
    if not ok:
        raise AssertionError('FAIL ' + what + (': ' + str(detail) if detail else ''))
    checks += 1
    print('PASS: ' + what, flush=True)


def attempt(what, step):
    try:
        return step()
    except Exception as error:
        failures.append(what)
        print(str(error) if str(error).startswith('FAIL') else 'FAIL: ' + what + ': ' + repr(error)[:3000], flush=True)
        return None


def cells(title, values, column=0):
    """One titled worksheet column as the form sends a selection of it: a number as the cell shows it, a blank cell as empty text."""
    def text(value):
        if value is None:
            return ''
        return str(int(value)) if isinstance(value, (int, float)) and float(value).is_integer() else str(value)
    last = len(values) + 1
    return {'source': f'{WORKBOOK} / Data · rows 2–{last}', 'range': {'firstRow': 2, 'lastRow': last, 'columns': [column]},
            'preserveRows': True, 'columns': [{'title': title, 'values': [text(v) for v in values]}],
            'worksheet': {'workbook': WORKBOOK, 'workbookPath': '/nonexistent/' + WORKBOOK, 'sheet': 0, 'sheetName': 'Data',
                          'hasTitle': True, 'titles': [title]}}


def walk(session, operation, answers, until=None):
    """The operation through the Mac host, each prompt answered by name as Windows's host fills each parameter; a prompt the answers do
    not name fails. Stops when the host refuses an answer (it presents the same prompt again with the validator's message), after
    the answer to the prompt named until, or at the end of the run. Returns (the prompts as first presented, by name; the last state)."""
    ident, state = session.start(operation, PREFS)
    seen = {}
    try:
        for _ in range(100):
            if state.get('state') != 'input':
                break
            prompt = state['prompt']
            name = prompt.get('name')
            if prompt.get('error'):
                break
            seen[name] = prompt
            if name not in answers:
                raise AssertionError(f'{operation} asked for {name} ({prompt["kind"]}), which these checks do not answer')
            session.request(action='answer', id=ident, token=state['token'], value=answers[name])
            state = session.wait(ident)
            if name == until:
                break
        return seen, state
    finally:
        session.close(ident)


def refusal(state):
    """(the prompt, the message) when the host refused the last answer, else None."""
    prompt = state.get('prompt') if state.get('state') == 'input' else None
    return (prompt.get('name'), prompt['error']) if prompt and prompt.get('error') else None


def outcome(state):
    """What the run came to, for a failure's message: the refusal, or the state with the engine's error."""
    return refusal(state) or (state.get('state'), state.get('error'), (state.get('prompt') or {}).get('name'))


def definition(operation, frame):
    """(mode, validator names) of the frame in the operation definition the engine under test loads."""
    beside = ENGINE.resolve().parent   # FullEngine/publish in the source tree; Contents/Frameworks in the app, whose definitions are in Contents/Resources/Engine
    folders = [folder / 'Operations' for folder in (beside, beside.parent / 'Resources/Engine')]
    path = next((folder for folder in folders if folder.is_dir()), folders[0]) / (operation + '.xml')
    found = [node for node in ET.parse(path).iter(SCHEMA + 'frame') if node.findtext(SCHEMA + 'name') == frame]
    assert len(found) == 1, (str(path), frame, len(found))
    names = [node.findtext(SCHEMA + 'name') for node in found[0].iter(SCHEMA + 'validator')]
    return found[0].findtext(SCHEMA + 'mode'), names


def before(operation):
    """The answers that bring the operation to its identifier or category frame (five rows for the time series summary)."""
    if operation == 'TimeSeriesSummary':
        return {'times': cells('Time', [0, 0, 1, 1, 2], 0), 'observations': cells('Level', [1, 2, 3, 4, 5], 1)}
    return {'type': 'categories'}


def output_columns(state):
    """The columns of the worksheet output the run returns, under their titles: Windows's parameters["output"].AsDataFrame."""
    frame = state['frames'][0]
    grid = {(c['col'], c['row']): c['text'] for c in frame['cells']}
    return [[grid.get((column, row)) for row in range(1, frame['rows'])] for column in range(frame['columns'])]


def tables(html):
    return [[[re.sub(r'<[^>]+>', '', c).strip() for c in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>', row, re.S)]
             for row in re.findall(r'<tr[^>]*>(.*?)</tr>', part.split('</table>', 1)[0], re.S)]
            for part in html.split('<table')[1:]]


def means_by_time(html):
    """The Mean column of the report's table by time; exactly one group, as Windows's Single() requires."""
    by_time = [t for t in tables(html) if t and t[0][:3] == ['Time', 'Observations', 'Mean']]
    assert len(by_time) == 1 and html.count('<h2>Group:') == 1, [t[0] for t in tables(html)]
    return [float(row[2]) for row in by_time[0][1:]]


def defined(session, operation, frame):
    column = 2 if operation == 'TimeSeriesSummary' else 0
    answers = dict(before(operation), **{frame: cells('Subject', SELECTIONS[2][1], column)})
    seen, _ = walk(session, operation, answers, until=frame)
    mode, validators = definition(operation, frame)
    check(frame in seen and seen[frame].get('mode') == CATEGORY and mode == CATEGORY and 'NoMissingData' in validators,
          f'{operation} {frame} deserializes its category mode and its NoMissingData',
          (seen.get(frame, {}).get('mode'), mode, validators))


def selected(session, operation, frame, label, values):
    column = 2 if operation == 'TimeSeriesSummary' else 0
    answers = dict(before(operation), **{frame: cells('Subject', values, column)})
    _, state = walk(session, operation, answers, until=frame)
    if label != 'every value present':
        check(refusal(state) == (frame, NO_MISSING), f'{operation} {frame} with {label} is refused by NoMissingData', outcome(state))
    elif operation == 'TimeSeriesSummary':
        # accepted: no message, and the host goes on to the next parameter
        check(state.get('state') == 'input' and not state['prompt'].get('error') and state['prompt'].get('name') == 'groups',
              f'{operation} {frame} with {label} is accepted', outcome(state))
    else:
        # accepted: the contraction runs, and counts each of the five cells
        check(state.get('state') == 'complete' and output_columns(state) == [['p1', 'p2', 'p3', 'p4'], ['1', '2', '1', '1']],
              f'{operation} {frame} with {label} is accepted',
              outcome(state) if state.get('state') != 'complete' else output_columns(state))


def summarised(session, blank):
    answers = {'times': cells('Time', [0, 0, 1, 1], 0), 'observations': cells('Level', [1, 2, 3, 4], 1),
               'subjectIds': cells('Subject', ['p1', 'p2', None if blank else 'p1', 'p2'], 2),
               'groups': {'skip': True}, 'ci': 95, 'doExactP': False}
    _, state = walk(session, 'TimeSeriesSummary', answers)
    if blank:
        check(refusal(state) == ('subjectIds', NO_MISSING),
              'time series summary with a blank subject identifier stops at its validation message', outcome(state))
    else:
        check(state.get('state') == 'complete' and means_by_time(state['html']) == [1.5, 3.5],
              'time series summary with complete identifiers gives its means by time',
              outcome(state) if state.get('state') != 'complete' else means_by_time(state['html']))


def contracted(session, blank):
    answers = {'type': 'categories', 'categories': cells('Category', ['red', 'blue', None if blank else 'red', 'blue'], 0)}
    _, state = walk(session, 'ContractFrequencies', answers)
    if blank:
        check(refusal(state) == ('categories', NO_MISSING),
              'contraction of frequencies with a blank category stops at its validation message', outcome(state))
    else:
        columns = output_columns(state) if state.get('state') == 'complete' else None
        check(columns is not None and columns[0] == ['red', 'blue'] and [float(v) for v in columns[-1]] == [2.0, 2.0],
              'contraction of frequencies with complete categories counts each category', columns or outcome(state))


if __name__ == '__main__':
    session = Session()
    try:
        for operation, frame in FRAMES:
            attempt(f'{operation} {frame} definition', lambda: defined(session, operation, frame))
            for label, values in SELECTIONS:
                attempt(f'{operation} {frame} with {label}', lambda: selected(session, operation, frame, label, values))
        for blank in (True, False):
            attempt('time series summary, ' + ('blank' if blank else 'complete'), lambda: summarised(session, blank))
            attempt('contraction of frequencies, ' + ('blank' if blank else 'complete'), lambda: contracted(session, blank))
    finally:
        session.finish()
    print(f'NO MISSING IDENTIFIERS: {checks} checks passed, {len(failures)} failed', flush=True)
    if failures:
        raise SystemExit('FAIL: ' + '; '.join(failures))
