import test from 'node:test';
import assert from 'node:assert/strict';
import {worksheetCommands, matchingWorksheetCommands} from './worksheet-commands.mjs';

const catalogue = [
  {id:'TPaired', label:'Paired t', title:'Paired Student t test', path:['Analysis','Parametric']},
  {id:'TPaired', label:'Paired samples', path:['Analysis','Comparison']},
  {id:'RankSum', label:'Mann–Whitney U', path:['Analysis','Nonparametric']},
  {id:'Plot', label:'Histogram', path:['Graphics'], disabled:true},
  {id:'Transform', label:'Logarithm', path:['Data','Transform']}
];

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
  assert.deepEqual(matchingWorksheetCommands(commands, 'paired t test').map(command=>command.path),
    [['Analysis','Parametric']]);
  assert.deepEqual(matchingWorksheetCommands(commands, 'mann whitney').map(command=>command.id), ['RankSum']);
  assert.deepEqual(matchingWorksheetCommands(commands, 'data log').map(command=>command.id), ['Transform']);
  assert.equal(matchingWorksheetCommands(commands, 'unmatched method').length, 0);
  assert.deepEqual(matchingWorksheetCommands(commands, '').map(command=>command.path[0]),
    ['Analysis','Analysis','Analysis','Data','Graphics']);
});

test('Paired t ranks ahead of an earlier Unpaired t menu entry when Enter selects a match', () => {
  const commands = worksheetCommands([{id:'TUnpaired',label:'Unpaired t',path:['Analysis','Parametric']}, ...catalogue]);
  assert.equal(matchingWorksheetCommands(commands, 'paired t')[0].id, 'TPaired');
});

test('incomplete or unrelated records cannot become worksheet commands', () => {
  assert.deepEqual(worksheetCommands(null), []);
  assert.deepEqual(worksheetCommands([null, {}, {id:'',label:'Empty',path:['Analysis']},
    {id:'x',label:'Other',path:['File']}, {id:'x',label:'Bad path',path:['Analysis',null]}]), []);
});
