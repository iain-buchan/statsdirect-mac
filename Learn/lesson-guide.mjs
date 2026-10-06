// Imported provider lessons can omit these optional curated-library fields.
export function lessonGuideHTML(lesson, catalogue, esc, safeURL) {
  const list=values=>`<ul>${values.map(value=>`<li>${esc(value)}</li>`).join('')}</ul>`;
  const section=(title,html)=>html?`<h3>${esc(title)}</h3>${html}`:'';
  let html=`<p>${esc(lesson.summary)}</p><p>${esc(lesson.steps)}</p>`;
  if(lesson.learningObjectives?.length)html+=section('What you will learn',list(lesson.learningObjectives));
  if(lesson.prerequisites?.length)html+=`<p><strong>Useful preparation:</strong> ${lesson.prerequisites.map(id=>esc(catalogue.find(l=>l.id===id)?.title??id)).join('; ')}.</p>`;
  if(lesson.keyConcepts?.length)html+=section('Key ideas',lesson.keyConcepts.map(c=>`<p><strong>${esc(c.term)}.</strong> ${esc(c.explanation)}</p>`).join(''));
  if(lesson.workedExample)html+=section('Interpreting this example',`<p>${esc(lesson.workedExample.design)}</p><p>${esc(lesson.workedExample.interpretation)}</p>`);
  if(lesson.misconceptions?.length)html+=section('Common mistakes',lesson.misconceptions.map(m=>`<p><strong>${esc(m.claim)}</strong><br>${esc(m.correction)}</p>`).join(''));
  if(lesson.teachingPrompts?.length)html+=section('Think it through',list(lesson.teachingPrompts.map(p=>p.prompt)));
  if(lesson.rProgression)html+=section('From menus to R',list([lesson.rProgression.menus,lesson.rProgression.bridge,lesson.rProgression.coding]));
  if(lesson.sources?.length)html+=section('References and further reading',`<ul>${lesson.sources.map(s=>`<li>${safeURL(s.url)?`<a href="${esc(safeURL(s.url))}" target="_blank" rel="noopener">${esc(s.title)}</a>`:esc(s.title)} — ${esc(s.scope)}</li>`).join('')}</ul><p class="small">Original StatsDirect teaching material. Sources checked ${esc(lesson.review?.date)}; external subject-expert review pending.</p>`);
  return html;
}
