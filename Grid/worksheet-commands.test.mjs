import test from 'node:test';
import assert from 'node:assert/strict';
import {worksheetCommands, worksheetCommandsWithSharedLabels, worksheetSearchMatches} from './worksheet-commands.mjs';

const catalogue = [
  {id:'TPaired', label:'Paired t', title:'Paired Student t test', path:['Analysis','Parametric']},
  {id:'TPaired', label:'Paired samples', path:['Analysis','Comparison']},
  {id:'RankSum', label:'Mann–Whitney U', path:['Analysis','Nonparametric']},
  {id:'Plot', label:'Histogram', path:['Graphics'], disabled:true},
  {id:'Transform', label:'Logarithm', path:['Data','Transform']}
];

function orderedMatches(commands, query) {
  const {exact, related, other} = worksheetSearchMatches(commands, query);
  return [...exact, ...related, ...other];
}

test('the chooser preserves native order, duplicate operation placements and disabled state', () => {
  const commands = worksheetCommands(catalogue);
  assert.equal(commands.length, 5);
  assert.deepEqual(commands.map(command=>command.id), catalogue.map(command=>command.id));
  assert.equal(commands[3].disabled, true);
  assert.equal(commands[0].title, 'Paired Student t test');
  catalogue[0].path.push('Later mutation');
  assert.deepEqual(commands[0].path, ['Analysis','Parametric']);
  catalogue[0].path.pop();
});

test('search matches the native label, full analysis title and menu categories', () => {
  const commands = worksheetCommands(catalogue);
  assert.deepEqual(orderedMatches(commands, 'paired t test').map(command=>command.path),
    [['Analysis','Parametric']]);
  assert.deepEqual(orderedMatches(commands, 'mann whitney').map(command=>command.id), ['RankSum']);
  assert.deepEqual(orderedMatches(commands, 'data log').map(command=>command.id), ['Transform']);
  assert.equal(orderedMatches(commands, 'unmatched method').length, 0);
  assert.deepEqual(orderedMatches(commands, '').map(command=>command.path[0]),
    ['Analysis','Analysis','Analysis','Data','Graphics']);
});

test('Paired t ranks ahead of an earlier Unpaired t menu entry when Enter selects a match', () => {
  const commands = worksheetCommands([{id:'TUnpaired',label:'Unpaired t',path:['Analysis','Parametric']}, ...catalogue]);
  assert.equal(orderedMatches(commands, 'paired t')[0].id, 'TPaired');
});

test('exact labels and titles outrank partial matches from earlier menus', () => {
  const commands = worksheetCommands([
    {id:'Growth', label:'Growth Charts', title:'Anthropometric Z-Scores', path:['Analysis','Clinical Epidemiology']},
    {id:'Scale', label:'Z Score', path:['Data','Common Transforms']},
    {id:'Draw', label:'Plot', title:'Z Score', path:['Graphics']}
  ]);
  const {exact, other} = worksheetSearchMatches(commands, 'z score');
  assert.deepEqual(exact.map(command => command.id), ['Scale', 'Draw']);
  assert.deepEqual(other.map(command => command.id), ['Growth']);
});

test('overlapping labels retain their menu paths even when search selects only one', () => {
  const commands = worksheetCommands([
    {id:'Normal', label:'Normal', path:['Analysis','Distributions']},
    {id:'RandomNormal', label:'Normal…', path:['Data','Generating','Random Numbers']},
    {id:'RandomPoisson', label:'Poisson', path:['Data','Generating','Random Numbers']}
  ]);
  const shared = worksheetCommandsWithSharedLabels(commands);
  assert.deepEqual([...shared], commands.slice(0, 2));
  assert.deepEqual(orderedMatches(commands, 'normal random'), [commands[1]]);
  assert.equal(shared.has(commands[1]), true);
});

test('Help keyword aliases find commands whose names do not match', () => {
  const commands = worksheetCommands([
    {id:'TPaired', label:'Paired t', path:['Analysis','Parametric'], helpKeywords:['Bland Altman plot', null, '']},
    {id:'Other', label:'Other', path:['Analysis','Other']}
  ]);
  assert.deepEqual(commands[0].helpKeywords, ['Bland Altman plot']);
  assert.deepEqual(orderedMatches(commands, 'bland-altman').map(command => command.id), ['TPaired']);
});

test('paired design results use reviewed methods and preserve named method searches', () => {
  const commands = worksheetCommands([
    ...catalogue,
    {id:'Wilcoxon', label:'Wilcoxon Signed Ranks', path:['Analysis','Nonparametric']},
    {id:'ExactMcNamarChi', label:'McNemar', path:['Analysis','Chi-square Tests']},
    {id:'PropPairs', label:'Paired', title:'Paired proportions', path:['Analysis','Proportions']},
    {id:'Chi2by2', label:'2 by 2', path:['Analysis','Chi-square Tests'], helpKeywords:['Paired tests']},
    {id:'TUnpaired', label:'Unpaired t', path:['Analysis','Parametric']},
    {id:'SizePaired', label:'Paired sample size', path:['Analysis','Sample Size']},
    {id:'LadderPlot', label:'Ladder', title:'Ladder plot for paired observations', path:['Graphics'], helpKeywords:['Paired tests']},
    {id:'ExactSign', label:'Sign', path:['Analysis','Exact Tests on Counts'], disabled:true}
  ]);
  const ids = query => worksheetSearchMatches(commands, query).related.map(command => command.id);
  assert.deepEqual(ids('paired tests'), ['TPaired','Wilcoxon','ExactMcNamarChi','PropPairs']);
  assert.deepEqual(ids('same participants before and after'), ids('paired tests'));
  assert.deepEqual(ids('paired binary outcomes'), ['ExactMcNamarChi','PropPairs']);
  assert.deepEqual(ids('paired t test'), []);
  assert.equal(orderedMatches(commands, 'paired t test')[0].id, 'TPaired');
  assert.equal(orderedMatches(commands, 'unpaired t')[0].id, 'TUnpaired');
  assert.deepEqual(worksheetSearchMatches(commands, 'paired').other.map(command => [command.id, command.path]),
    [['LadderPlot',['Graphics']]]);
  assert.deepEqual(worksheetSearchMatches(commands, 'paired tests').other, []);
});

test('incomplete or unrelated records cannot become worksheet commands', () => {
  assert.deepEqual(worksheetCommands(null), []);
  assert.deepEqual(worksheetCommands([null, {}, {id:'',label:'Empty',path:['Analysis']},
    {id:'x',label:'Other',path:['File']}, {id:'x',label:'Bad path',path:['Analysis',null]}]), []);
});
