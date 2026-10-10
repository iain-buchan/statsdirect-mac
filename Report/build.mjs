import { fileURLToPath } from 'node:url';
import {build} from 'esbuild';
import {readFile,writeFile,readdir,realpath} from 'node:fs/promises';
await build({entryPoints:[fileURLToPath(new URL('./export.mjs',import.meta.url))],bundle:true,format:'iife',globalName:'StatsDirectReportExport',target:'safari17',outfile:fileURLToPath(new URL('../Content/Report/export.js',import.meta.url)),legalComments:'eof',minify:true});
for (const [name,globalName] of [['import','StatsDirectReportImport'],['editor','StatsDirectReportEditor']]) await build({entryPoints:[fileURLToPath(new URL('./'+name+'.mjs',import.meta.url))],bundle:true,format:'iife',globalName,target:'safari17',outfile:fileURLToPath(new URL('../Content/Report/'+name+'.js',import.meta.url)),legalComments:'eof',minify:true});
let notice='StatsDirect reports use docx (MIT), DOMPurify (Apache-2.0 or MPL-2.0), and emf-converter (Apache-2.0), bundled for offline use.\nhttps://github.com/dolanmiu/docx\nhttps://github.com/cure53/DOMPurify\nhttps://github.com/ChristopherVR/emf-converter\n\n';
// Follow the installed production graph, excluding stale versions left in pnpm's
// virtual store after upgrades. This keeps notices reproducible on a clean CI install.
const included=new Map();
async function visit(directory) {
  const canonical=await realpath(directory).catch(()=>null);
  if(!canonical||included.has(canonical))return;
  const pkg=JSON.parse(await readFile(canonical+'/package.json','utf8'));
  if(pkg.name.startsWith('@types/'))return;
  included.set(canonical,pkg);
  const modules=canonical.slice(0,canonical.lastIndexOf('/node_modules/')+14);
  for(const name of Object.keys({...pkg.dependencies,...pkg.optionalDependencies}).sort())await visit(modules+name);
}
const manifest=JSON.parse(await readFile(new URL('./package.json',import.meta.url),'utf8'));
for(const name of Object.keys(manifest.dependencies).sort())await visit(new URL('./node_modules/'+name,import.meta.url));
for(const [directory,pkg] of [...included].sort((a,b)=>a[1].name.localeCompare(b[1].name))) {
  const files=await readdir(directory);
  const licence=files.find(n=>/^licen[cs]e(\.|$)/i.test(n));
  let terms=licence?await readFile(directory+'/'+licence,'utf8'):null;
  if(!terms){const readme=await readFile(directory+'/README.md','utf8').catch(()=>'');terms=readme.match(/^#+ LICENSE[\s\S]*$/im)?.[0];}
  if(!terms)throw new Error('Missing licence for bundled report dependency '+pkg.name);
  notice+=`\n--- ${pkg.name} ${pkg.version} ---\n`+terms+'\n';
  for(const extra of ['NOTICE','THIRD_PARTY_NOTICES'])if(files.includes(extra))notice+=`\n--- ${pkg.name}: ${extra} ---\n`+await readFile(directory+'/'+extra,'utf8')+'\n';
}
await writeFile(new URL('../Content/Report/THIRD-PARTY-LICENSES.txt',import.meta.url),notice.replace(/\r\n/g,'\n'));
