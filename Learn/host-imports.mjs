// The shared Learning package (Learn/Upstream/Learning, from statisticalhelp) has two imports that each host supplies:
// the lessons the page bundles ('../Content/Learn/lessons.json') and bank.mjs, the provenance shim. This esbuild plugin
// points both at the Mac's files whenever a module inside the package imports them; the Windows build remaps the same two.
import {fileURLToPath} from 'node:url';
const shared=fileURLToPath(new URL('./Upstream/Learning/',import.meta.url));
export const hostImports={name:'statsdirect-learning-host',setup(b){
  b.onResolve({filter:/^\.\.\/Content\/Learn\/lessons\.json$/},args=>args.importer.startsWith(shared)?{path:fileURLToPath(new URL('../Content/Learn/lessons.json',import.meta.url))}:undefined);
  b.onResolve({filter:/^\.\/bank\.mjs$/},args=>args.importer.startsWith(shared)?{path:fileURLToPath(new URL('./bank.mjs',import.meta.url))}:undefined);
}};
