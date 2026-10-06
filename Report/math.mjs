import {Math as Equation,MathRun,MathFraction,MathRadical,MathSubScript,MathSuperScript,MathSubSuperScript,MathLimitLower,MathLimitUpper} from 'docx';

// KaTeX provides semantic MathML as well as a visual HTML representation.
// Export the semantic tree once as an editable Word equation, without its
// duplicate HTML or TeX annotation.
function runs(node) {
  if(!node)return [];
  const c=[...node.children],all=()=>c.flatMap(runs),at=i=>runs(c[i]);
  switch(node.localName) {
    case 'annotation':case 'annotation-xml':case 'mphantom':case 'mspace':return [];
    case 'semantics':return at(0);
    case 'mi':case 'mn':case 'mo':case 'mtext':case 'ms':return [new MathRun(node.textContent)];
    case 'mfrac':return [new MathFraction({numerator:at(0),denominator:at(1)})];
    case 'msqrt':return [new MathRadical({children:all()})];
    case 'mroot':return [new MathRadical({children:at(0),degree:at(1)})];
    case 'msub':return [new MathSubScript({children:at(0),subScript:at(1)})];
    case 'msup':return [new MathSuperScript({children:at(0),superScript:at(1)})];
    case 'msubsup':return [new MathSubSuperScript({children:at(0),subScript:at(1),superScript:at(2)})];
    case 'mover': {
      const mark={'¯':'\u0304','‾':'\u0304','ˉ':'\u0304','^':'\u0302','ˆ':'\u0302','~':'\u0303','˜':'\u0303'}[c[1]?.textContent];
      if(mark&&[...c[0].textContent].length===1)return [new MathRun(c[0].textContent+mark)];
      return [new MathLimitUpper({children:at(0),limit:at(1)})];
    }
    case 'munder':return [new MathLimitLower({children:at(0),limit:at(1)})];
    case 'munderover':return [new MathLimitUpper({children:[new MathLimitLower({children:at(0),limit:at(1)})],limit:at(2)})];
    case 'mtable':return [new MathRun('['),...c.flatMap((row,i)=>[...(i?[new MathRun('; ')]:[]),...runs(row)]),new MathRun(']')];
    case 'mtr':return c.flatMap((cell,i)=>[...(i?[new MathRun(', ')]:[]),...runs(cell)]);
    default:return c.length?all():node.textContent?[new MathRun(node.textContent)]:[];
  }
}
export function wordEquation(element) {
  const math=element.localName==='math'?element:element.querySelector('math');
  return math?new Equation({children:runs(math)}):null;
}
