// Archived 12-question concept, using the maintained teaching bank.
import {bankVersion, tracks as allTracks, questions as allQuestions} from '../../Learn/bank.mjs';
export {bankVersion};
export const tracks = Object.fromEntries(['foundation','medicine','publicHealth'].map(id => [id, allTracks[id]]));
const ids = new Set(['UG-SENS-01','UG-NNT-01','UG-PVAL-01','UG-PAIR-01',
  'PG-PPV-01','PG-CI-01','PG-RROR-01','PG-SE-01',
  'PH-STAND-01','PH-CONF-01','PH-CLUST-01','PH-SMR-01']);
export const questions = allQuestions.filter(q => ids.has(q.id));
