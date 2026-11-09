"""The 5.3.8 post-release meta-analysis checks through the Mac operation host and R (Windows tests/RScript/PosthocMeta537.cs at f24edb13).

As on Windows, each analysis runs through the engine's own operation, here through the Mac host's prompts answered with worksheet
columns that carry their provenance (each frame's columns from the top of a sheet, as PosthocMetaFrame537 acquires them), and the R
script is the one the engine's writer (statsdirect_r_script) makes from the record the run left with its report, run in R with the
checks' assertions after it.

The risk difference meta-analysis with the exact preference on, at 80, 90, 95 and 99%: R's Miettinen-Nurminen study limits
(risk-difference.R) are the engine's and an independent reference's (the constrained proportions solved from the likelihood's
derivative, not from the recipe's cubic), with R's warnings made errors; and the recipe's score interval for four tables whose
estimate is on the boundary has the engine's finite endpoints (MathDbl.uppci) at 80, 95 and 99%.

The analyses that take the exact method from the host's preference and, since 5.3.8, record it once per analysis as the input
metaExact (RptMantel, RptEffect for d and for the weighted mean difference, RptMetaCorrelation and RptProportionMeta), and the typed-in
Mantel-Haenszel screen, whose own try_exact answer is the method whatever the preference (so it runs with the opposite one), at 80, 95
and 99%, each with the exact method and without it: the record keeps the method the run used, as a setting and not a result; a record
written again from the analysis's bag after the host preference has changed keeps it; the script binds exact_meta from it; R's
I-squared and its limits are the engine's, and for the odds ratio analyses so are each study's limits (the Woolf limits without the
exact method), labelled with the method, the pooled exact block printed only with it; and the record without the setting (as a record
from before 5.3.8 is) replays the exact method: I-squared's limits are the engine's exact ones for the run's Q and the odds ratios'
limits those of the exact run.

What the Mac snapshot does not return is read otherwise, and each place says so: block outputs (each study's limits) from the native
report printed to 12 decimal places, far inside the 2e-7 tolerance; what the Windows check takes from the analysis's bag or from engine
functions directly (MathDbl.uppci, Meta.IsquareNcc, the direction of the recorded input, RunRecord.Write after the preference changes,
and the effect size analysis's I-squared, a block output the report prints to one decimal place) from one C# script run by the same
Mac host (its UserScript operation, the managed route of test_pr6_replay.py), whose builtin figures are first checked against the Mac
runs' own. Run as python3 Tests/test_posthoc_meta.py [operation-driver]; the test's files are kept under .build only when it fails.
"""
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
from r_runtime import rscript
from test_menu import ROOT, Session
from test_pr6_replay import RWriter, sheet
from test_shared_engine_update import ReportText

RSCRIPT = rscript()
LIBRARY = Path(os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib')))
MISSING = -1.7976931348623157e308   # Constant.MISSING (double.MinValue), a missing figure, as RunRecord.Missing reads it
SKIP = {'skip': True}               # an optional prompt skipped, as the Windows checking host answers null
# The confidence level is asked at each run, as the Windows checking host never defaults it; the native report prints its figures to
# 12 decimal places, where each study's limits are read. The Windows host leaves its other preferences at their type defaults (a
# continuity correction of 0, the Mac's default being the treatment arm), but no table here has an empty cell, so none is corrected.
PREFERENCES = {'use-default-ci': False, 'decp': '12', 'pdecp': '7'}
NUMBER = r'-?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][-+]?\d+)?'

# CheckPosthocRiskDifference537's tables: symmetric, unequal and null studies, none with an empty cell
N1 = [20, 20, 50, 50, 10, 100, 200, 16]
A = [8, 16, 13, 30, 4, 50, 100, 12]
N2 = [20, 20, 50, 50, 10, 100, 200, 8]
B = [12, 4, 37, 20, 6, 50, 100, 3]
# CheckPosthocMetaMethods537's studies
SN = [615, 758, 832, 317, 810, 2267, 8587]
SR = [49, 44, 102, 32, 85, 246, 1570]
XN = [624, 771, 850, 309, 406, 2257, 8600]
XR = [67, 64, 126, 38, 52, 219, 1720]
LEFT = [count for events, total in zip(SR, SN) for count in (events, total - events)]    # the screen's tables: cases then non-cases
RIGHT = [count for events, total in zip(XR, XN) for count in (events, total - events)]
EFFECT = {'en': [27, 16, 25, 62, 9, 63, 23], 'em': [18.5, 60, 10.72, 9.2, 3.75, 60, 9.24], 'es': [14.9, 29.2, 6.46, 6.16, 2.55, 13.3, 5.35],
          'cn': [17, 15, 66, 66, 22, 40, 23], 'cm': [5.4, 55, 6.92, 6.92, 1.05, 46.3, 5.33], 'cs': [17.3, 29.2, 6.83, 6.83, 2.12, 18.6, 4.48]}
CORRELATION = {'r': [.3, .52, .1, .45, .21, .60], 'n': [50, 80, 40, 120, 60, 90]}
PROPORTION = {'sn': [311, 65, 67, 285, 73, 116, 183, 696], 'sr': [214, 58, 59, 182, 65, 66, 99, 600]}
VARIANTS = ['Mantel', 'MantelHaenszelScreen', 'Effect-d', 'Effect-m', 'MetaCorrelation', 'ProportionMeta']
FIGURES = ('qc', 'isq', 'llisq', 'ulisq')

checks = 0
def check(ok, what):
    global checks
    if not ok:
        raise AssertionError('FAIL ' + what)
    checks += 1
    print('PASS:', what, flush=True)


def operation_of(variant):
    return 'Effect' if variant.startswith('Effect-') else variant


def missing(value):
    return value is None or value == MISSING or not math.isfinite(value)


def r_vector(values):
    """RScriptWriter.Vector of the figures, a missing one (RunRecord.Missing) as NA."""
    return 'c(' + ', '.join('NA' if missing(v) else repr(float(v)) for v in values) + ')'


def equal(expression, values, tolerance=2e-7):
    """PosthocMetaEqual537: R's figures and the engine's agree to all.equal's relative tolerance."""
    return ('stopifnot(isTRUE(all.equal(unname(c(' + expression + ')),as.numeric(' + r_vector(values) + '),tolerance=' + repr(tolerance) +
            ',check.attributes=FALSE)))\n')


def worksheet(*columns):
    """Numeric worksheet columns with their provenance, titled as PosthocMetaFrame537's grid titles them (the Mac grid's bridge, sheet())."""
    return sheet(['Column %d' % (i + 1) for i in range(len(columns))], [list(column) for column in columns])


def run(session, operation, given, exact_preference):
    """The operation through the Mac host's prompts, with the meta-analyses' exact method as the host's preference, each prompt answered
    by its name from the given answers. Session.run would answer a prompt it is not given with its default; the Windows checking host
    refuses one instead, and so does this."""
    ident, state = session.start(operation, {**PREFERENCES, 'meta-exact': exact_preference})
    try:
        for _ in range(100):
            if state.get('state') != 'input':
                break
            prompt = state['prompt']
            if prompt.get('error') or prompt.get('name') not in given:
                raise AssertionError('FAIL %s asked for %s (%s), which these checks do not answer%s' % (
                    operation, prompt.get('name'), prompt.get('kind'), ': ' + prompt['error'] if prompt.get('error') else ''))
            session.request(action='answer', id=ident, token=state['token'], value=given[prompt['name']])
            state = session.wait(ident)
    finally:
        session.close(ident)
    if state.get('state') != 'complete':
        raise AssertionError('FAIL %s did not complete: %s %s' % (operation, state.get('state'), state.get('error')))
    return state


def report_number(text):
    if not re.fullmatch(NUMBER, text):
        raise AssertionError('FAIL the native report printed %r where a figure was expected' % text)
    return float(text)


def study_limits(snapshot, first, pct):
    """Each study's limits, lower then upper, from the native report's table of them: the Mac snapshot's values are the scalar results
    only, not the per-study rows the Windows check reads from the bag, and the report prints them to 12 decimal places."""
    rows = ReportText(snapshot['html']).rows
    heading = ['Stratum', first, '%d%% CI (%s)' % (pct, snapshot['values']['method'])]
    for i, row in enumerate(rows):
        if row[:3] == heading:
            body = []
            for line in rows[i + 1:]:
                if not line or not line[0].isdigit():
                    break
                body.append(line)
            if [int(line[0]) for line in body] != list(range(1, len(body) + 1)) or any(len(line) < 4 for line in body):
                raise AssertionError('FAIL the native table headed %s is not one row per study: %s' % (heading, body))
            return [report_number(line[2]) for line in body], [report_number(line[3]) for line in body]
    raise AssertionError('FAIL the native report has no table headed %s' % heading)


def effect_report(snapshot, pct):
    """The effect size analysis's Cochran Q (12 decimal places) and I-squared with its limits (one decimal place), as its report prints them."""
    text = ReportText(snapshot['html']).text
    q = re.search(r'Cochran Q = (' + NUMBER + r') ', text)
    i2 = re.search(r'I² \(inconsistency\) = (' + NUMBER + r')%\s*\(\s*' + str(pct) + r'% CI = (' + NUMBER + r')% to (' + NUMBER + r')%\s*\)', text)
    if not q or not i2:
        raise AssertionError('FAIL the effect size report gives no Cochran Q and I-squared at %d%%: %s' % (pct, text[:3000]))
    return float(q[1]), [float(i2[k]) for k in (1, 2, 3)]


def run_r(code, folder, timeout=60):
    """DeferredR538: the script in its own folder, run by Rscript --vanilla, with a time limit; its output and timing kept there."""
    folder.mkdir(parents=True, exist_ok=True)
    script = folder / 'script.R'
    script.write_text(code, encoding='utf-8')
    environment = dict(os.environ)
    for name in ('LC_ALL', 'LC_CTYPE'):
        if environment.get(name) == 'C.UTF-8':
            environment.pop(name)
    started = time.monotonic()
    try:
        # on a timeout subprocess.run stops only the R process it started, as DeferredR538 does
        result = subprocess.run([RSCRIPT, '--vanilla', '--encoding=UTF-8', str(script)], cwd=folder, env=environment,
                                capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise AssertionError('FAIL R exceeded %d seconds in %s' % (timeout, folder))
    (folder / 'elapsed-ms.txt').write_text(str(round(1000 * (time.monotonic() - started))))
    (folder / 'stdout.txt').write_text(result.stdout)
    (folder / 'stderr.txt').write_text(result.stderr)
    if result.returncode != 0:
        raise AssertionError('FAIL R in %s:\n%s\n%s' % (folder, result.stdout, result.stderr))
    return result.stdout


def verify(writer, record, assertions, folder, no_warnings=False):
    """VerifyPosthocMeta537: the script the engine writes from the record, with the assertions after it."""
    script = writer.write(record)
    check(script['hasRecipe'] and not script['dataUnavailable'], folder.name + ' records the selected data and method')
    output = run_r(('options(warn=2)\n' if no_warnings else '') + script['text'] + '\n' + assertions + "\ncat('POSTHOC_META_OK\\n')\n", folder)
    check('POSTHOC_META_OK' in output, folder.name + ' agrees with the native and R interval references')
    return output


# --- what the Windows check takes from the analysis's bag or from engine functions directly, through the Mac host's C# script operation.
# The builtins are called with the analyses' inputs and the run's preference, as the operations' builtin steps call them; their
# figures are checked against the Mac runs' own below before any is used.
NATIVE_SCRIPT = r'''
var inv = CultureInfo.InvariantCulture;
string R(double x) => RunRecord.Missing(x) ? "NA" : x.ToString("R", inv);
DataFrame F(params double[][] columns) {
    var frame = new DataFrame();
    for (int i = 0; i < columns.Length; i++) frame.Variables.Add(new DoubleVariable(columns[i], "Column " + (i + 1)));
    return frame;
}
IEnumerable<ParameterBag> Bags(ParameterBag bag) {
    yield return bag;
    foreach (var pair in bag.Pairs)
        if (pair.Value?.AsObject is IList<ParameterBag> children)
            foreach (var child in children) foreach (var item in Bags(child)) yield return item;
}
double Number(ParameterBag bag, string key) => Convert.ToDouble(Bags(bag).First(b => b.ContainsKey(key) && b[key]?.AsObject != null)[key].AsObject, inv);

// the risk difference score interval's endpoints for four tables whose estimate is on the boundary
foreach (double confidence in new[] { .8, .95, .99 }) {
    double critical = PDF.gauinv((1 + confidence) / 2);
    MathDbl.uppci(10, 10, 0, 10, out double l1, out double u1, critical, confidence * 100);
    MathDbl.uppci(0, 10, 10, 10, out double l2, out double u2, critical, confidence * 100);
    MathDbl.uppci(20, 20, 0, 3, out double l3, out double u3, critical, confidence * 100);
    MathDbl.uppci(0, 7, 21, 21, out double l4, out double u4, critical, confidence * 100);
    Console.WriteLine("UPPCI " + R(confidence) + " " + string.Join(" ", new[] { l1, u1, l2, u2, l3, u3, l4, u4 }.Select(R)));
}

double[] sn = @SN, sr = @SR, xn = @XN, xr = @XR, left = @LEFT, right = @RIGHT;
double[] en = @EN, em = @EM, es = @ES, cn = @CN, cm = @CM, cs = @CS, r = @CR, n = @CNN, psn = @PSN, psr = @PSR;
foreach (string variant in new[] { "Mantel", "MantelHaenszelScreen", "Effect-d", "Effect-m", "MetaCorrelation", "ProportionMeta" })
foreach (double confidence in new[] { .8, .95, .99 })
foreach (bool exact in new[] { true, false }) {
    string operation = variant.StartsWith("Effect-", StringComparison.Ordinal) ? "Effect" : variant;
    bool screen = operation == "MantelHaenszelScreen";
    string setting = screen ? "try_exact" : "metaExact";
    host.Preferences.MetaExact = screen ? !exact : exact;
    var inputs = new ParameterBag();
    if (screen) { inputs.AddInput("data", F(left, right)); inputs.AddInput("cco", confidence); inputs.AddInput("plot_forest", false); inputs.AddInput("try_exact", exact); }
    else inputs.AddInput("gamma", confidence);
    if (operation == "Mantel") { inputs.AddInput("sn", F(sn)); inputs.AddInput("sr", F(sr)); inputs.AddInput("xn", F(xn)); inputs.AddInput("xr", F(xr)); }
    if (operation == "Effect") {
        inputs.AddInput("type", variant.Substring(variant.Length - 1));
        inputs.AddInput("en", F(en)); inputs.AddInput("em", F(em)); inputs.AddInput("es", F(es));
        inputs.AddInput("cn", F(cn)); inputs.AddInput("cm", F(cm)); inputs.AddInput("cs", F(cs));
    }
    if (operation == "MetaCorrelation") { inputs.AddInput("r", F(r)); inputs.AddInput("n", F(n)); }
    if (operation == "ProportionMeta") { inputs.AddInput("method", "arcsine"); inputs.AddInput("sn", F(psn)); inputs.AddInput("sr", F(psr)); }
    ParameterBag output = (operation switch {
        "Mantel" => Meta.RptMantel(host, inputs),
        "MantelHaenszelScreen" => Chi.RptChiMantel(host, inputs),
        "Effect" => Meta.RptEffect(host, inputs),
        "MetaCorrelation" => Meta.RptMetaCorrelation(host, inputs),
        _ => Meta.RptProportionMeta(host, inputs)
    }).ParameterBag;
    // the analysis's bag as its report step holds it, the inputs with the builtin's results; then the record written again from it after
    // the host preference changes, as the Windows check writes it again from the run
    var bag = inputs.Copy();
    foreach (var pair in output.Pairs) bag[pair.Key] = pair.Value;
    FilledParameter recorded = bag[setting];
    host.Preferences.MetaExact = !host.Preferences.MetaExact;
    string replay = RunRecord.Write(new OperationRun(new Operation { Name = operation }), bag);
    string key = variant + " " + R(confidence) + " " + exact;
    Console.WriteLine("BAG " + key + " " + recorded.Direction + " " + recorded.AsBoolean + " " + string.Join(" ", new[] { "qc", "isq", "llisq", "ulisq" }.Select(k => R(Number(bag, k)))));
    Console.WriteLine("REPLAY " + key + " " + replay);
    if (!exact && confidence == .95) {
        // the interval an older record, which has no method, replays: the exact one, for the run's Q
        int studies = operation == "MetaCorrelation" ? 6 : operation == "ProportionMeta" ? 8 : 7;
        Meta.IsquareNcc(host, Number(bag, "qc"), studies, confidence, PDF.gauinv((1 + confidence) / 2), out double point, out double lower, out double upper, exact: true);
        Console.WriteLine("LEGACY " + variant + " " + R(point) + " " + R(lower) + " " + R(upper));
    }
}
'''


def cs_array(values):
    return 'new double[] { ' + ', '.join(repr(float(v)) for v in values) + ' }'


def natives(session):
    code = NATIVE_SCRIPT
    for name, values in [('@SN', SN), ('@SR', SR), ('@XN', XN), ('@XR', XR), ('@LEFT', LEFT), ('@RIGHT', RIGHT),
                         ('@EN', EFFECT['en']), ('@EM', EFFECT['em']), ('@ES', EFFECT['es']), ('@CN', EFFECT['cn']), ('@CM', EFFECT['cm']),
                         ('@CS', EFFECT['cs']), ('@CR', CORRELATION['r']), ('@CNN', CORRELATION['n']), ('@PSN', PROPORTION['sn']), ('@PSR', PROPORTION['sr'])]:
        code = re.sub(re.escape(name) + r'\b', cs_array(values), code)
    ident = str(uuid.uuid4())
    try:
        started = session.request(action='start', id=ident, operation='UserScript', language='CSharp', script=code,
                                  preferences={**PREFERENCES, 'meta-exact': True})
        if started.get('error'):
            raise AssertionError('FAIL the C# script of the native figures did not start: %s' % started['error'])
        state = session.wait(ident)
        if state['state'] != 'complete':
            raise AssertionError('FAIL the C# script of the native figures: %s %s\n%s' % (state['state'], state.get('error'), state.get('console')))
    finally:
        session.close(ident)
    figure = lambda text: None if text == 'NA' else float(text)
    native = {'uppci': {}, 'bags': {}, 'replays': {}, 'legacy': {}}
    for line in state['console'].splitlines():
        kind, _, rest = line.partition(' ')
        if kind == 'UPPCI':
            confidence, *values = rest.split()
            native['uppci'][confidence] = [figure(v) for v in values]
        elif kind == 'BAG':
            variant, confidence, exact, direction, recorded, *values = rest.split()
            native['bags'][(variant, confidence, exact == 'True')] = {'direction': direction, 'recorded': recorded == 'True',
                                                                      **{k: figure(v) for k, v in zip(FIGURES, values)}}
        elif kind == 'REPLAY':
            variant, confidence, exact, record = rest.split(' ', 3)
            native['replays'][(variant, confidence, exact == 'True')] = json.loads(record)
        elif kind == 'LEGACY':
            variant, *values = rest.split()
            native['legacy'][variant] = [figure(v) for v in values]
    if len(native['uppci']) != 3 or len(native['bags']) != 36 or len(native['replays']) != 36 or len(native['legacy']) != 6:
        raise AssertionError('FAIL the C# script did not give every native figure:\n' + state['console'])
    return native


# --- CheckPosthocRiskDifference537
MN_REFERENCE = '''mn_reference <- function(a,n1,b,n2) {
  est <- a/n1-b/n2
  score <- function(delta) {
    if (delta == est) return(0)
    slope <- function(p2) {
      p1 <- p2+delta
      a/p1-(n1-a)/(1-p1)+b/p2-(n2-b)/(1-p2)
    }
    p2 <- uniroot(slope,c(max(0,-delta)+1e-12,min(1,1-delta)-1e-12),tol=1e-14)$root
    p1 <- p2+delta
    variance <- (p1*(1-p1)/n1+p2*(1-p2)/n2)*(n1+n2)/(n1+n2-1)
    (est-delta)/sqrt(variance)
  }
  c(uniroot(function(d) score(d)-z,c(-1+1e-8,est),tol=1e-12)$root,
    uniroot(function(d) score(d)+z,c(est,1-1e-8),tol=1e-12)$root)
}
reference <- t(mapply(mn_reference,a,n1,b,n2))
stopifnot(max(abs(ci-reference)) < 1e-9)
'''


def published_recipe(name):
    """A recipe as the engine publishes it beside itself: FullEngine/publish in the source tree; in the app, whose engine library
    is in Contents/Frameworks, Contents/Resources/Engine."""
    library = LIBRARY.resolve()
    for folder in (library.parent, library.parent.parent / 'Resources/Engine'):
        if (folder / 'R/recipes' / name).is_file():
            return (folder / 'R/recipes' / name).read_text()
    raise FileNotFoundError(name + ' is not published beside ' + str(library))


def risk_difference(session, writer, native, folder):
    for pct in (80, 90, 95, 99):
        confidence = pct / 100
        snapshot = run(session, 'RiskDifference', {'gamma': pct, 'strata': SKIP, 'sn': worksheet(N1), 'sr': worksheet(A),
                                                   'xn': worksheet(N2), 'xr': worksheet(B)}, True)
        # Independently estimate the constrained proportions by solving the binomial likelihood derivative, avoiding the recipe's cubic.
        lower, upper = study_limits(snapshot, 'Risk difference', pct)
        assertion = equal('ci[,1],ci[,2]', lower + upper) + MN_REFERENCE
        verify(writer, json.loads(snapshot['record']), assertion, folder / ('symmetric-and-unequal-' + repr(confidence)), no_warnings=True)

    # Test the two finite boundary endpoints directly, independently of the unrelated pooling/weight handling for studies with empty
    # cells: the recipe's function, as the engine publishes it beside itself, against the engine's own (MathDbl.uppci, by the C# script).
    recipe = published_recipe('risk-difference.R')
    start = recipe.index('mn_limits <- function')
    limits = recipe[start:recipe.index('if (isTRUE(exact_meta))', start)]
    for pct in (80, 95, 99):
        confidence = pct / 100
        result = run_r('options(warn=2)\nz <- qnorm(' + repr((1 + confidence) / 2) + ')\n' + limits +
                       equal('mn_limits(10,10,0,10),mn_limits(0,10,10,10),mn_limits(20,20,0,3),mn_limits(0,7,21,21)', native['uppci'][repr(confidence)]) +
                       "cat('POSTHOC_BOUNDARY_OK\\n')\n", folder / ('endpoints-' + repr(confidence)))
        check('POSTHOC_BOUNDARY_OK' in result, 'risk difference score interval has the native finite endpoints at ' + repr(confidence))


# --- CheckPosthocMetaMethods537
WOOLF = ('stopifnot(max(abs(lci-exp(log(a*d/(b*c))-z*sqrt(1/a+1/b+1/c+1/d))))<1e-10,\n'
         'max(abs(uci-exp(log(a*d/(b*c))+z*sqrt(1/a+1/b+1/c+1/d))))<1e-10)\n')


def answers(variant, pct, exact):
    """The Windows check's answers under the Mac prompts' names, the confidence level as the percentage the prompt takes."""
    operation = operation_of(variant)
    if operation == 'Mantel':
        return {'gamma': pct, 'strata': SKIP, 'sn': worksheet(SN), 'sr': worksheet(SR), 'xn': worksheet(XN), 'xr': worksheet(XR)}
    if operation == 'MantelHaenszelScreen':
        # the screen's table as the Windows check gives it, a numeric frame with its provenance (the Mac form would send it typed, as an
        # entered frame: the same figures, and a script that replays them the same way)
        return {'cco': pct, 'try_exact': exact, 'plot_forest': False, 'data': worksheet(LEFT, RIGHT)}
    if operation == 'Effect':
        # g is asked only for effect sizes given as g, so neither run asks it
        return {'gamma': pct, 'type': variant[-1], 'strata': SKIP, 'g': SKIP, **{name: worksheet(v) for name, v in EFFECT.items()}}
    if operation == 'MetaCorrelation':
        return {'gamma': pct, 'studies': SKIP, **{name: worksheet(v) for name, v in CORRELATION.items()}}
    return {'gamma': pct, 'method': 'arcsine', 'strata': SKIP, **{name: worksheet(v) for name, v in PROPORTION.items()}}


def same_figure(a, b):
    return (missing(a) and missing(b)) or (not missing(a) and not missing(b) and a == b)


def meta_methods(session, writer, native, folder):
    for variant in VARIANTS:
        operation = operation_of(variant)
        screen = operation == 'MantelHaenszelScreen'
        odds = operation == 'Mantel' or screen
        setting = 'try_exact' if screen else 'metaExact'
        for pct in (80, 95, 99):
            confidence = pct / 100
            exact_reference = None
            for exact in (True, False):
                # The typed-in screen's answer takes precedence over the app preference.
                snapshot = run(session, operation, answers(variant, pct, exact), (not exact) if screen else exact)
                record = json.loads(snapshot['record'])
                key = (variant, repr(confidence), exact)
                bag = native['bags'][key]
                label = '%s-%s-%r' % (variant, exact, confidence)

                # The builtin's own bag (the C# script) must be this run's: its Q and I-squared figures are the run's results exactly,
                # or, for the effect size analysis, whose figures are a block output, the run's report's (Q to 12 places, I-squared to 1).
                if operation == 'Effect':
                    q, i2 = effect_report(snapshot, pct)
                    same = (abs(q - bag['qc']) <= 1e-12 * max(1, abs(q)) and
                            all(not missing(b) and abs(printed - b) <= 0.05 + 1e-9 for printed, b in zip(i2, [bag[k] for k in FIGURES[1:]])))
                else:
                    same = all(same_figure(snapshot['values'].get(k), bag[k]) for k in FIGURES)
                check(same, label + ' builtin bag gives the Mac run\'s Q and I-squared')

                # The Windows check reads the run's bag; here the record says where the setting went (RunRecord.Write puts a setting in
                # "parameters" and a result in "values"), the bag of the builtin that recorded it gives its direction, and the screen's
                # setting is the run's own answer to its prompt.
                as_setting = setting not in record['values'] and setting not in snapshot['values']
                if screen:
                    answered = [i.get('value') for i in record['inputs'] if i.get('name') == setting]
                    from_run = answered == [exact]
                else:
                    from_run = bag['direction'] == 'Input' and bag['recorded'] is exact and snapshot['record'].count('"metaExact"') == 1
                check(record['parameters'].get(setting) is exact and as_setting and from_run, label + ' records the method used by the native operation')

                # On the Mac the record a script is written from is the one the report step left (the snapshot's), never written again; the
                # Windows check's second writing, after the host preference has changed, is that of the builtin's bag in the C# script.
                replay = native['replays'][key]
                check(replay['parameters'].get(setting) is exact, label + ' keeps the recorded method when the host preference changes')

                mode = 'TRUE' if exact else 'FALSE'
                # I-squared and its limits: the run's results, or, for the effect size analysis, its builtin's bag at full precision
                figures = [bag[k] for k in FIGURES[1:]] if operation == 'Effect' else [snapshot['values'].get(k) for k in FIGURES[1:]]
                assertion = 'stopifnot(identical(exact_meta,' + mode + '))\n' + equal('i2,i2_ci', figures)
                if odds:
                    limits = study_limits(snapshot, 'Odds ratio', pct)
                    if exact:
                        exact_reference = limits
                    assertion += equal('lci,uci', limits[0] + limits[1]) + "stopifnot(exists('cml',inherits=FALSE)==" + mode + ')\n'
                    if not exact:
                        assertion += WOOLF
                result = verify(writer, record, assertion, folder / label)
                if odds:
                    check(('CI (' + ('CML' if exact else 'logit') + ')') in result and ('Exact mid-P' in result) == exact,
                          label + ' labels the selected study limits and prints the pooled exact block only when selected')

                if not exact and pct == 95:
                    legacy = json.loads(snapshot['record'])
                    del legacy['parameters'][setting]
                    legacy_assertion = 'stopifnot(isTRUE(exact_meta))\n' + equal('i2,i2_ci', native['legacy'][variant])
                    if odds:
                        legacy_assertion += equal('lci,uci', exact_reference[0] + exact_reference[1]) + "stopifnot(exists('cml',inherits=FALSE))\n"
                    verify(writer, legacy, legacy_assertion, folder / (label + '-legacy'))


if __name__ == '__main__':
    (ROOT / '.build').mkdir(exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='posthoc-meta-', dir=ROOT / '.build'))
    session, writer = Session(), RWriter()
    passed = False
    try:
        native = natives(session)
        risk_difference(session, writer, native, temporary / 'posthoc-meta' / 'risk-difference')
        meta_methods(session, writer, native, temporary / 'posthoc-meta' / 'meta-methods')
        passed = True
    except Exception as error:
        message = str(error)
        print(message if message.startswith('FAIL') else 'FAIL ' + traceback.format_exc(), flush=True)
        print('Retained test artifacts: ' + str(temporary), flush=True)
    finally:
        writer.close()
        session.finish()
    if not passed:
        sys.exit(1)
    shutil.rmtree(temporary)
    print('PASS: %d post-release meta-analysis checks' % checks, flush=True)
