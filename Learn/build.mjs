import { fileURLToPath } from 'node:url';
import {build} from '../Grid/node_modules/esbuild/lib/main.js';
await build({entryPoints:[fileURLToPath(new URL('./app.mjs',import.meta.url))],bundle:true,format:'iife',target:'safari17',outfile:fileURLToPath(new URL('../Content/Learn/app.js',import.meta.url))});
const {cp,readFile,writeFile,mkdir}=await import('node:fs/promises');
await mkdir(new URL('../Content/Learn/katex/',import.meta.url),{recursive:true});
for(const file of ['katex.min.css','fonts'])await cp(new URL('./node_modules/katex/dist/'+file,import.meta.url),new URL('../Content/Learn/katex/'+file,import.meta.url),{recursive:true});
const licenses=[];
for(const name of ['dompurify','katex','highlight.js']){
 const pkg=JSON.parse(await readFile(new URL(`./node_modules/${name}/package.json`,import.meta.url),'utf8'));
 const {readdir}=await import('node:fs/promises');
 const root=new URL(`./node_modules/${name}/`,import.meta.url);
 for(const file of await readdir(root))if(/^licen[cs]e/i.test(file))licenses.push(`${name} ${pkg.version}\n`+await readFile(new URL(file,root),'utf8'));
}
await writeFile(new URL('../Content/Learn/THIRD-PARTY-LICENSES.txt',import.meta.url),licenses.join('\n\n'));
