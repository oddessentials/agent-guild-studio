import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [pieces, root] = process.argv.slice(2);
if (!pieces || !root) throw new Error('Usage: node tools/check_with_agent_guild.mjs <folder of piece folders> <agent-guild checkout>');
const { checkModels } = await import(pathToFileURL(path.join(root, 'src/manager/yard-piece-check.mjs')).href);
const MODELS = { character: ['character.glb'], companion: [0, 1, 2, 3].map((n) => `companion_${n}.glb`) };

let checked = 0;
let refused = 0;
for (const entry of fs.readdirSync(pieces, { withFileTypes: true })) {
  const folder = path.join(pieces, entry.name);
  if (!entry.isDirectory() || !fs.existsSync(path.join(folder, 'piece.json'))) continue;
  const { kind } = JSON.parse(fs.readFileSync(path.join(folder, 'piece.json'), 'utf8'));
  if (!MODELS[kind]) throw new Error(`${entry.name}: piece.json names no kind agent-guild takes`);
  checked += 1;
  try {
    await checkModels(MODELS[kind].map((name) => ({ path: path.join(folder, name), name })), kind);
    console.log(`ok       ${entry.name} (${kind})`);
  } catch (err) {
    refused += 1;
    console.log(`REFUSED  ${entry.name} (${kind}): ${err.message}`);
  }
}
console.log(`${checked - refused} of ${checked} pieces pass agent-guild's check`);
if (!checked || refused) process.exit(1);
