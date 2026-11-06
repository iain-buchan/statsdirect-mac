// The shared Learning code imports './bank.mjs', which each host supplies: the bundler remaps it in
// Learn/build.mjs, and this resolver does the same for node when a module under Learn/Upstream/Learning imports it.
const shared = new URL('./Upstream/Learning/', import.meta.url).href;
const bank = new URL('./bank.mjs', import.meta.url).href;
export async function resolve(specifier, context, next) {
  if (specifier === './bank.mjs' && context.parentURL?.startsWith(shared)) return {url: bank, shortCircuit: true};
  return next(specifier, context);
}
