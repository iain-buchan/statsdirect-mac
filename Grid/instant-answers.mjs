export const promptKey = p => `${p.name}:${p.kind}`;
// Replays edited answers through the real host so every parameter is validated again.
// A newly enabled question, or any rejected value, returns to the normal input form.
export class InstantAnswers {
  constructor() { this.steps=new Map(); this.replay=null; }
  record(prompt,value) { this.steps.set(promptKey(prompt),{p:{...prompt,error:null},value}); }
  restart(steps) { this.replay=new Map(steps.map(s=>[promptKey(s.p),s.value]));this.steps.clear(); }
  next(prompt) {
    const key=promptKey(prompt);
    if(prompt.error || !this.replay?.has(key))return {found:false};
    const value=this.replay.get(key);this.replay.delete(key);this.record(prompt,value);
    return {found:true,value};
  }
  finish() { this.replay=null;return [...this.steps.values()]; }
}
