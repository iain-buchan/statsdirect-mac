"""Which results the report offers a continuation in R: the engine's answer for each record, as the Windows report's.

The Windows report labels an entry's R command by the recipe its script writer would use for the record
(RRecipes.Find of the record), where it had looked at the operation alone. A follow-on whose recipe depends on the
analysis it continued (the regression ANOVA, the principal components and the dose-response follow-ons) has one
only when its record names that analysis or lets the writer infer it, so a saved result that does neither is
offered its data and settings rather than "Continue in R", which could only have told the user to rerun.

The Mac asks the engine the same question: for a report or a notebook it reopens, with a {"recipes": [records]}
request of statsdirect_r_script, and for a run in hand, in the recipe flag of its completed snapshot. Every answer
here is also compared with the writer's own choice for the same record, so the label cannot promise a script the
writer would not write. No R is needed: what the scripts compute is test_run_record.py's and
test_recipe_regressions.py's to check.
"""
import json
import os
import subprocess
import uuid

from test_menu import ROOT, Session

ENGINE = os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT/'FullEngine/publish/StatsDirectEngine.dylib'))
UNIDENTIFIED = 'The saved result does not identify its original analysis. Rerun that analysis to reproduce this follow-on in R.'
manifest = json.loads((ROOT/'Content/R/analysis-recipes.json').read_text())
routed = {operation: entry['parentFiles'] for operation, entry in manifest.items() if entry.get('parentFiles')}
writer = subprocess.Popen([str(ROOT/'Tests/engine-driver'), ENGINE, 'statsdirect_r_script'],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)


def call(request):
    writer.stdin.write(json.dumps(request) + '\n')
    writer.stdin.flush()
    return json.loads(writer.stdout.readline())


def covered(records):
    """The engine's answer for each record, in the order asked."""
    reply = call({'recipes': records})
    assert list(reply) == ['recipes'] and len(reply['recipes']) == len(records), reply
    assert all(flag is True or flag is False for flag in reply['recipes']), reply
    return reply['recipes']


def written(record):
    """The writer's reply for the record with no data supplied: its script and choice of recipe, or its error."""
    return call({'record': record, 'frames': []})


def check(label, cases):
    """cases: (what, record, expected). Asked in one request, so the order of the answers is checked with them,
    then each compared with the writer: its HasRecipe, and no recipe where it cannot write from the record at all."""
    answers = covered([record for _, record, _ in cases])
    wrong = [(what, expected, answer) for (what, _, expected), answer in zip(cases, answers) if answer is not expected]
    assert not wrong, (label, wrong)
    for (what, record, _), answer in zip(cases, answers):
        reply = written(record)
        assert answer is (reply.get('hasRecipe') is True), (label, what, answer, {k: v for k, v in reply.items() if k != 'text'})
    return len(cases)


def named(*items):
    return {'source': 'Recipe by record checks', 'columns': [{'title': title, 'values': values} for title, values in items]}


def without(record, *settings):
    """The record as an older version saved it: naming no analysis it continued and, where given, lacking those settings."""
    legacy = {name: value for name, value in record.items() if name != 'rootOperation'}
    if settings:
        legacy['parameters'] = {name: value for name, value in record['parameters'].items() if name not in settings}
    return legacy


try:
    # --- every operation of the shared manifest: an ordinary method has its recipe whatever its record names; a follow-on
    # routed by its parent has one for each analysis it may continue, and none for a record naming no analysis or another
    assert all(isinstance(entry.get('file'), str) for entry in manifest.values())
    assert {'Cronbach', 'PCRCoefficients', 'PCRMatrix', 'PCRScores', 'ProbitInterpolateX', 'ProbitInterpolateY', 'ProbitMore', 'ProbitPlot', 'Ranv'} <= set(routed), sorted(routed)
    cases = []
    for operation in manifest:
        cases.append((operation + ' alone', {'operation': operation}, operation not in routed))
        cases.append((operation + ' naming an analysis it does not continue, as JSON text', json.dumps({'operation': operation, 'rootOperation': 'NoSuchMethod'}), operation not in routed))
        for parent in routed.get(operation, {}):
            cases.append((operation + ' after ' + parent, {'operation': operation, 'rootOperation': parent}, True))
    count = check('manifest', cases)
    print(f'PASS: the recipes request answers for all {len(manifest)} operations of the shared manifest as the writer chooses ({count} records): '
          f'the {len(routed)} follow-ons routed by their parent have a recipe after each of their parents and none alone', flush=True)

    # --- saved results as older versions left them, by name: what the record lets the writer infer, and no more
    legacy = [
        ('a paired t test', {'operation': 'TPaired'}, True),
        ('a paired t test, whatever analysis its record names', {'operation': 'TPaired', 'rootOperation': 'NoSuchMethod'}, True),
        ('component scores after the correlation analysis', {'operation': 'PCRScores', 'rootOperation': 'PCRCorrelation'}, True),
        ('component scores after the covariance analysis', {'operation': 'PCRScores', 'rootOperation': 'PCRCovariance'}, True),
        ('component scores naming no analysis', {'operation': 'PCRScores', 'parameters': {'components': 2}}, False),
        ('component scores naming a regression', {'operation': 'PCRScores', 'rootOperation': 'SimpleLinearRegression'}, False),
        ('component coefficients naming no analysis', {'operation': 'PCRCoefficients', 'parameters': {}}, False),
        ('the component matrix naming no analysis', {'operation': 'PCRMatrix'}, False),
        ('Cronbach\'s alpha naming no analysis', {'operation': 'Cronbach', 'parameters': {}}, False),
        ('a regression ANOVA after the simple regression', {'operation': 'Ranv', 'rootOperation': 'SimpleLinearRegression'}, True),
        ('a regression ANOVA after the linearized estimates', {'operation': 'Ranv', 'rootOperation': 'LinearizedEstimates'}, True),
        ('a regression ANOVA naming a paired t test', {'operation': 'Ranv', 'rootOperation': 'TPaired', 'parameters': {}}, False),
        ('a legacy regression ANOVA with settings and no model: the simple regression', {'operation': 'Ranv', 'parameters': {}}, True),
        ('a legacy regression ANOVA with a model among its settings: the linearized estimates', {'operation': 'Ranv', 'parameters': {'model': '1'}}, True),
        ('a legacy regression ANOVA whose named analysis is empty text', {'operation': 'Ranv', 'rootOperation': '', 'parameters': {}}, True),
        ('a regression ANOVA with neither settings nor a named analysis', {'operation': 'Ranv'}, False),
        ('a legacy dose-response plot of a probit fit', {'operation': 'ProbitPlot', 'parameters': {'doseResponseModel': 'probit'}}, True),
        ('a legacy dose-response follow-on of a logit fit', {'operation': 'ProbitMore', 'parameters': {'doseResponseModel': 'logit'}}, True),
        ('a dose-response follow-on of a link no recipe fits', {'operation': 'ProbitMore', 'parameters': {'doseResponseModel': 'cloglog'}}, False),
        ('a dose-response follow-on whose link is no text', {'operation': 'ProbitMore', 'parameters': {'doseResponseModel': 1}}, False),
        ('a dose-response interpolation with settings and no link', {'operation': 'ProbitInterpolateX', 'parameters': {'newx': 3}}, False),
        ('a dose-response interpolation with no settings', {'operation': 'ProbitInterpolateY'}, False),
        ('a box and whisker plot', {'operation': 'BoxWhiskerPlot'}, True),
        ('a box and whisker plot by Tukey\'s hinges', {'operation': 'BoxWhiskerPlot', 'parameters': {'boxWhisker': {'method': 7}}}, True),
        ('a method the manifest does not hold', {'operation': 'NoSuchMethod'}, False),
    ]
    count = check('legacy records', legacy)
    count += check('legacy records as JSON text', [(what, json.dumps(record), expected) for what, record, expected in legacy])
    print(f'PASS: {count} named saved records, as objects and as JSON text: a follow-on naming no analysis has a recipe only where '
          'the writer infers it (the regression ANOVA from its settings, the dose-response follow-ons from their link)', flush=True)

    # --- nothing unreadable has a recipe, and none of it stops the request: the records beside it are still answered, in order
    unreadable = [('text that is not JSON', 'not a record'), ('empty text', ''), ('JSON text of a list', '[1]'), ('JSON text of nothing', 'null'),
                  ('a number', 5), ('nothing', None), ('a flag', True), ('a list', [{'operation': 'TPaired'}]),
                  ('an object naming no operation', {}), ('an operation that is not text', {'operation': 5}), ('an empty operation', {'operation': ''})]
    cases = []
    for what, record in unreadable:
        cases += [(what, record, False), ('a paired t test after ' + what, {'operation': 'TPaired'}, True)]
    count = check('unreadable records', cases)
    # settings that are not an object: the shared routing reads them as one, so the writer cannot write from such a record; whatever it
    # makes of them, the request is answered, with the writer's choice, and the records beside them are unaffected
    malformed = [{'operation': 'Ranv', 'parameters': 3}, {'operation': 'ProbitMore', 'parameters': None}, {'operation': 'PCRScores', 'parameters': [1]},
                 {'operation': 'BoxWhiskerPlot', 'parameters': 'x'}, {'operation': 'BoxWhiskerPlot', 'parameters': {'boxWhisker': 7}}]
    cases = []
    for record in malformed:
        cases += [(json.dumps(record), record, written(record).get('hasRecipe') is True), ('a paired t test after ' + json.dumps(record), {'operation': 'TPaired'}, True)]
    count += check('malformed settings', cases)
    assert covered([]) == []
    assert call({'recipes': 'x'}) == {'error': 'The request\'s recipes are not a list of records.'}
    assert call({'recipes': {'operation': 'TPaired'}}) == {'error': 'The request\'s recipes are not a list of records.'}
    print(f'PASS: {count} answers among unreadable records and settings that are no object: none has a recipe the writer would not write, '
          'the records beside them are answered in order, and a request that is no list is refused', flush=True)

    # --- Codex's routing fixtures (Tests/Fixtures/RecipeRouting): the 36 records the report export suite reopens from a saved report and
    # recovers from a notebook, each follow-on routed by its parent after an analysis the manifest names, after one it does not, and
    # alone. The answer expected of each is the fixture's own, written without the engine's rule to hand
    fixtures = ROOT/'Tests/Fixtures/RecipeRouting'
    matrix = json.loads((fixtures/'matrix.json').read_text())
    saved = json.loads((fixtures/'routing.html').read_text().split('<script type="application/json" id="statsdirect-report-data">')[1].split('</script>')[0])['entries']
    recovered = json.loads((fixtures/'routing.ipynb').read_text())['metadata']['statsdirect']['entries']
    assert len(matrix) == 36 and sum(case['expected'] is True for case in matrix) == 23 and all(case['expected'] in (True, False) for case in matrix)
    assert [entry['title'] for entry in saved] == [case['title'] for case in matrix]
    assert [(entry['title'], entry['operation'], entry['record']) for entry in recovered] == [(entry['title'], entry['operation'], entry['record']) for entry in saved]
    assert {entry['operation'] for entry in saved} - {'TPaired'} <= set(routed) and all(entry['record']['operation'] == entry['operation'] for entry in saved)
    cases = [(case['title'], entry['record'], case['expected']) for case, entry in zip(matrix, saved)]
    count = check('routing fixtures', cases) + check('routing fixtures as JSON text', [(what, json.dumps(record), expected) for what, record, expected in cases])
    print(f'PASS: {count} answers for the {len(cases)} routing fixtures, as objects and as JSON text, are the fixtures\' own: '
          f'{sum(expected for _, _, expected in cases)} with a recipe, {sum(not expected for _, _, expected in cases)} without', flush=True)

    # --- real runs: a follow-on run now names the analysis it continued, so its snapshot says recipe true and its record is covered;
    # the same record as an older version saved it is covered only where the writer can tell the analysis from what is left
    session = Session()
    try:
        multivariate = named(('First', [1, 2, 4, 3, 5, 7, 6, 8]), ('Second', [3, 1, 4, 6, 5, 8, 7, 9]), ('Third', [2, 3, 1, 4, 6, 5, 8, 7]))
        components = [('Cronbach', {}), ('PCRCoefficients', {}), ('PCRMatrix', {}), ('PCRScores', {})]
        doses = {'dose': named(('Dose', [1, 2, 3, 4, 5])), 'subjects': named(('Subjects', [20]*5)), 'responders': named(('Responders', [2, 5, 10, 15, 19])),
                 'nc': 0, 'calc-log10-doses': False, 'qld': 80}
        responses = [('ProbitMore', {}), ('ProbitPlot', {}), ('ProbitInterpolateX', {'newx': 3}), ('ProbitInterpolateY', {'newy': .65})]
        families = [
            ('PCRCorrelation', {'data': multivariate}, components),
            ('PCRCovariance', {'data': multivariate}, components),
            ('SimpleLinearRegression', {'x': named(('Selected X', [1, 2, 3, 4, 5, 6])), 'y': named(('Selected Y', [3, 4, 5, 7, 9, 11]))}, [('Ranv', {})]),
            ('LinearizedEstimates', {'y': named(('Selected Y', [2, 3, 5, 8, 13, 21, 34, 55])), 'x': named(('Selected X', [1, 2, 3, 4, 5, 6, 7, 8])), 'model': '0'}, [('Ranv', {})]),
            ('Probit', doses, responses),
            ('Logit', doses, responses),
        ]
        runs = 0
        relabelled = []
        for operation, answers, children in families:
            parent = session.run(operation, answers, keep=True)
            try:
                assert parent.get('recipe') is True and covered([parent['record']]) == [True], operation
                for child, settings in children:
                    follow = session.run(child, settings, parent=parent['id'])
                    record = json.loads(follow['record'])
                    assert follow.get('recipe') is True and record['operation'] == child and record.get('rootOperation') == operation, (operation, child, follow.get('recipe'), record.get('rootOperation'))
                    full = written(record)
                    assert full.get('hasRecipe') is True and full['detail'] == manifest[child]['detail'], (operation, child, full.get('detail'), full.get('error'))
                    legacy = without(record)
                    if operation.startswith('PCR'):
                        # nothing in the record tells the correlation analysis from the covariance one: data and settings only, and the
                        # script says why rather than giving the other analysis's figures
                        assert covered([follow['record'], record, legacy, json.dumps(legacy)]) == [True, True, False, False], (operation, child)
                        reply = written(legacy)
                        assert reply.get('hasRecipe') is False and reply['detail'] == UNIDENTIFIED and UNIDENTIFIED in reply['text'] and reply['text'] != full['text'], (operation, child, reply.get('detail'))
                        relabelled.append(child + ' after ' + operation)
                    else:
                        # the settings left tell which analysis it continued (a model for the linearized estimates and none for the
                        # simple regression; the link of the dose-response fit), and the script is the one the named analysis gives
                        assert covered([record, legacy]) == [True, True], (operation, child)
                        reply = written(legacy)
                        assert reply.get('hasRecipe') is True and reply['text'] == full['text'], (operation, child)
                        bare = without(record, 'doseResponseModel') if child != 'Ranv' else {name: value for name, value in legacy.items() if name != 'parameters'}
                        assert covered([legacy, bare, record]) == [True, False, True], (operation, child)
                        reply = written(bare)
                        assert reply.get('hasRecipe') is False and reply['detail'] == UNIDENTIFIED, (operation, child, reply.get('detail'))
                    runs += 1
            finally:
                session.close(parent['id'])
        assert runs == 18 and len(relabelled) == 8, (runs, relabelled)
        print(f'PASS: {runs} follow-ons run from their {len(families)} parents say recipe true and name the analysis continued; saved without that name, '
              f'the {len(relabelled)} principal components follow-ons are data and settings only, with the writer\'s reason, and the regression ANOVA and '
              'dose-response follow-ons keep the recipe of the analysis their settings identify', flush=True)
    finally:
        session.finish()

    # --- the contingency table analysis the Mac runs through its own entry: the same answer for the record it leaves
    analysis = subprocess.run([str(ROOT/'Tests/engine-driver'), ENGINE, 'statsdirect_analysis'], text=True, capture_output=True, timeout=120,
                              input=json.dumps({'action': 'run', 'id': str(uuid.uuid4()), 'input': {'counts': [[10, 5], [3, 12]], 'rowLabels': ['Exposed', 'Not exposed'],
                                                'columnLabels': ['Present', 'Absent'], 'doExact': False}}) + '\n')
    result = json.loads(analysis.stdout)
    assert result.get('recipe') is True and json.loads(result['record'])['operation'] == 'ExactChiRbyCScreen', {k: v for k, v in result.items() if k != 'html'}
    assert covered([result['record']]) == [True] and written(result['record']).get('hasRecipe') is True
    print('PASS: the r by c table analysis says recipe true for the record it leaves, as the writer chooses', flush=True)
finally:
    writer.stdin.close()
    writer.wait()
