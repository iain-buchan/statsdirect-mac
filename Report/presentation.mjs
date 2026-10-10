// CSSStyleDeclaration enumerates expanded border longhands, even when the
// original report used a shorthand. Allow only these inert presentation values.
export const borderProperties=['top','right','bottom','left'].flatMap(side=>
  ['width','style','color'].map(part=>`border-${side}-${part}`));
