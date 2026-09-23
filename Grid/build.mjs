import { build } from 'esbuild';
import { mkdir, writeFile, readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
process.chdir(fileURLToPath(new URL('.', import.meta.url)));
const out = new URL('../Content/Grid/', import.meta.url);
await mkdir(out, {
  recursive: true
});
const result = await build({
  absWorkingDir: fileURLToPath(new URL('.', import.meta.url)),
  metafile: true,
  entryPoints: ['main.tsx'],
  bundle: true,
  minify: true,
  format: 'iife',
  target: 'safari17',
  outfile: new URL('grid.js', out).pathname,
  define: {
    'process.env.NODE_ENV': '"production"'
  },
  legalComments: 'linked'
});
await writeFile(new URL('index.html', out), `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>StatsDirect data grid</title><link rel="stylesheet" href="grid.css"></head><body><div id="root"></div><div id="portal"></div><script src="grid.js"></script></body></html>`);
// Include license files for every package whose source reaches the runtime bundle.
const roots = new Set();
for (const input of Object.keys(result.metafile.inputs)) {
  const absolute = path.resolve(input),
    marker = absolute.lastIndexOf('/node_modules/');
  if (marker < 0) continue;
  const tail = absolute.slice(marker + 14).split('/');
  roots.add(absolute.slice(0, marker + 14) + tail.slice(0, tail[0].startsWith('@') ? 2 : 1).join('/'));
}
const notices = [];
for (const root of [...roots].sort()) {
  const pkg = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
  notices.push(`\n${pkg.name} ${pkg.version} — ${pkg.license ?? 'see license below'}\n`);
  for (const file of await readdir(root)) if (/^(licen[cs]e|copying|notice)(\.|$)/i.test(file)) {
    try {
      notices.push(await readFile(path.join(root, file), 'utf8'));
    } catch {}
  }
}
await writeFile(new URL('THIRD-PARTY-LICENSES.txt', out), notices.join('\n'));
