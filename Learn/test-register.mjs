// Registers the resolver that gives the shared Learning tests their host-side bank.mjs.
// Use: node --import ./Learn/test-register.mjs --test Learn/Upstream/Learning/*.test.mjs
import {register} from 'node:module';
register('./test-resolver.mjs', import.meta.url);
