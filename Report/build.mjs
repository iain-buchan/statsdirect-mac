import {build} from 'esbuild';
import {readFile,writeFile,readdir,realpath} from 'node:fs/promises';
await build({entryPoints:[new URL('./export.mjs',import.meta.url).pathname],bundle:true,format:'iife',globalName:'StatsDirectReportExport',target:'safari17',outfile:new URL('../Content/Report/export.js',import.meta.url).pathname,legalComments:'eof',minify:true});
let notice='StatsDirect report export uses docx 9.7.2 (MIT), bundled for offline use.\nhttps://github.com/dolanmiu/docx\n\n';
// The distributed docx build also embeds its runtime dependencies. Retain their licences.
const packages=new URL('./node_modules/.pnpm/',import.meta.url);
const included=new Set();
for(const folder of await readdir(packages)) {
  if(folder.startsWith('@esbuild')||folder.startsWith('esbuild@')||folder==='node_modules')continue;
  const base=new URL(folder+'/node_modules/',packages);
  for(const name of await readdir(base).catch(()=>[])) {
    if(name.startsWith('@'))continue;
    const dir=new URL(name+'/',base);
    const canonical=await realpath(dir).catch(()=>null);
    if(!canonical||included.has(canonical)||name==='undici-types')continue;
    included.add(canonical);
    const licence=(await readdir(dir).catch(()=>[])).find(n=>/^licen[cs]e(\.|$)/i.test(n));
    if(licence)notice+=`\n--- ${name} ---\n`+await readFile(new URL(licence,dir),'utf8')+'\n';
  }
}
await writeFile(new URL('../Content/Report/THIRD-PARTY-LICENSES.txt',import.meta.url),notice);
