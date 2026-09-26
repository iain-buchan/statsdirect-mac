import React from 'react';
import './result-preview.css';

export function ResultPreview({result,busy,onKeep}:{result:any,busy:boolean,onKeep:()=>void}) {
  if(!result)return null;
  return <section className="instant-result" aria-label="Analysis results">
    <div className="result-actions"><h2>Results</h2><button className="primary" disabled={busy||!!result.kept} onClick={onKeep}>{result.kept?`Added to ${result.kept}`:'Add to report'}</button></div>
    <iframe title="Analysis results preview" sandbox="" srcDoc={result.page}/>
    <p className="hint">These results use the last completed calculation. Add them to the report to keep a copy.</p>
  </section>;
}
