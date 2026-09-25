import {build} from '../Grid/node_modules/esbuild/lib/main.js';
await build({entryPoints:[new URL('./app.mjs',import.meta.url).pathname],bundle:true,format:'iife',target:'safari17',outfile:new URL('../Content/Learn/app.js',import.meta.url).pathname});
