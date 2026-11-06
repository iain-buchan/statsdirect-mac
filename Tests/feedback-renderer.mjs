import {recordHTML} from '../Learn/Upstream/Learning/record-html.mjs';
import {reviewRecord} from '../Learn/Upstream/Learning/portfolio.mjs';
window.feedbackRecord=state=>recordHTML(reviewRecord(state));
