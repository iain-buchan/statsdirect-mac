import {recordHTML} from '../Learn/record-html.mjs';
import {reviewRecord} from '../Learn/portfolio.mjs';
window.feedbackRecord=state=>recordHTML(reviewRecord(state));
