// Actual 26.9.0 logs OIDC bootstrap errors then listens with fresh password setup.
// Patch only that pinned release's initialization block before importing it.
import { readFileSync, writeFileSync } from 'node:fs';

if (process.env.ACTUAL_OPENID_ENFORCE !== 'true' ||
    !process.env.ACTUAL_OPENID_DISCOVERY_URL ||
    !process.env.ACTUAL_OPENID_CLIENT_ID ||
    !process.env.ACTUAL_OPENID_CLIENT_SECRET) {
  throw new Error('Actual requires complete enforced OIDC configuration');
}
const path = '/app/chunks/app-D8uk2K_7.js';
const original = '\t\t\tif ("error" in result && result.error) console.log(result.error);\n' +
  '\t\t\telse console.log("OpenID configured!");\n' +
  '\t\t} catch (err) {\n\t\t\tconsole.error(err);\n\t\t}';
const replacement = '\t\t\tif ("error" in result && result.error) throw new Error("OIDC bootstrap failed");\n' +
  '\t\t\telse console.log("OpenID configured!");\n' +
  '\t\t} catch {\n\t\t\tconsole.error("OIDC bootstrap failed; refusing to listen"); process.exit(1);\n\t\t}';
const source = readFileSync(path, 'utf8');
if (source.split(original).length === 2) {
  writeFileSync(path, source.replace(original, replacement));
} else if (source.split(replacement).length !== 2) {
  throw new Error('Actual startup code changed; review OIDC failure handling before upgrade');
}
await import('/app/app.js');
