// Bundles a host-side entry that imports the shared Learning package, with the package's two host imports remapped
// (Learn/build.mjs bundles the page the same way). Use: node Learn/bundle.mjs <entry.mjs> <outfile.js>
import {fileURLToPath} from 'node:url';
import {build} from '../Grid/node_modules/esbuild/lib/main.js';
import {hostImports} from './host-imports.mjs';
const [entry,outfile]=process.argv.slice(2);
if(!entry||!outfile){console.error('Use: node Learn/bundle.mjs <entry.mjs> <outfile.js>');process.exit(2);}
await build({entryPoints:[entry],bundle:true,format:'iife',target:'safari17',absWorkingDir:fileURLToPath(new URL('../',import.meta.url)),outfile,plugins:[hostImports]});
