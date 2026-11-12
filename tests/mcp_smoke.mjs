// Drives the app's MCP server the way an agent's client does:
// node tests/mcp_smoke.mjs path/to/AgentGuildStudio.exe [godot arguments, such as --path .]
// (on a Mac, the executable inside AgentGuildStudio.app/Contents/MacOS)
// With STUDIO_ART naming a folder that holds the art packs, it also makes a
// character from STUDIO_SMOKE_MODEL and checks it.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const [exe, ...before] = process.argv.slice(2);
const appData = fs.mkdtempSync(path.join(os.tmpdir(), 'ags-mcp-'));
const args = [...before, '--headless', '--no-header', '--', '--mcp'];
// Studio keeps its data under APPDATA on Windows and under HOME on a Mac.
const child = spawn(exe, args, { stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, APPDATA: appData, ...(process.platform === 'darwin' ? { HOME: appData } : {}) } });
const lines = [];
const waiting = new Map();
let buffer = '';
let stderr = '';
child.stderr.setEncoding('utf8').on('data', (d) => { stderr += d; });
child.stdout.setEncoding('utf8').on('data', (d) => {
  buffer += d;
  let at;
  while ((at = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, at).replace(/\r$/, '');
    buffer = buffer.slice(at + 1);
    if (!line) continue;
    lines.push(line);
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }
    waiting.get(msg.id)?.(msg);
  }
});
const exited = new Promise((resolve) => child.on('exit', (code) => resolve(code)));
let nextId = 1;
const request = (method, params, timeoutMs = 60000) => new Promise((resolve, reject) => {
  const id = nextId++;
  const timer = setTimeout(() => reject(new Error(`${method} got no reply in ${timeoutMs} ms`)), timeoutMs);
  waiting.set(id, (msg) => { clearTimeout(timer); waiting.delete(id); resolve(msg); });
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
});
const tool = async (name, args, timeoutMs) => (await request('tools/call', { name, arguments: args }, timeoutMs)).result;
const failures = [];
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) failures.push(what); };

try {
  const init = await request('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'smoke', version: '1' } });
  check(init.result?.protocolVersion === '2025-11-25' && init.result?.serverInfo?.name === 'agent-guild-studio', 'initialize');
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  const meta = { 'io.modelcontextprotocol/protocolVersion': '2026-07-28', 'io.modelcontextprotocol/clientCapabilities': {} };
  const discover = await request('server/discover', { _meta: meta });
  check(discover.result?.supportedVersions?.includes('2026-07-28'), 'server/discover');
  const list = await request('tools/list', {});
  check(list.result?.tools?.map((t) => t.name).join() === 'list_slots,make_character,make_companions,recolor_look,check_piece,list_pieces,remove_piece,show_window', 'tools/list has the eight tools');
  child.stdin.write('{not json\n');
  const slots = await tool('list_slots', {});
  check(slots?.structuredContent?.worlds?.length === 6 && slots.structuredContent.worlds.every((w) => w.slots.length === 7), 'list_slots lists six worlds of seven slots');
  const empty = path.join(appData, 'empty');
  fs.mkdirSync(empty);
  const none = await tool('check_piece', { folder: empty });
  check(none?.isError === false && none.structuredContent?.passes === false && /piece\.json/.test(none.structuredContent.reason), 'check_piece says why an empty folder is no piece');
  const bad = await tool('make_character', { model: 'x.glb', slot: 'guild/nobody', to: empty });
  check(bad?.isError === true && /slot/.test(bad.content[0].text), 'make_character refuses a slot that does not exist');
  if (process.env.STUDIO_ART && process.env.STUDIO_SMOKE_MODEL) {
    const to = path.join(appData, 'made');
    const made = await tool('make_character', { model: process.env.STUDIO_SMOKE_MODEL, slot: 'gnomeland/openai', to, title: 'Smoke' }, 300000);
    check(made?.isError === false && fs.existsSync(path.join(to, 'character.glb')) && fs.existsSync(path.join(to, 'piece.json')), `make_character writes a piece (${made?.content?.[0]?.text?.slice(0, 120)})`);
    const again = await tool('make_character', { model: process.env.STUDIO_SMOKE_MODEL, slot: 'gnomeland/openai', to }, 300000);
    check(again?.isError === true && /already holds files/.test(again.content[0].text), 'make_character never writes over a folder that holds files');
    const passes = await tool('check_piece', { folder: to }, 120000);
    check(passes?.structuredContent?.passes === true && passes.structuredContent.slot === 'gnomeland/openai', 'check_piece passes the piece it made');
    const recolored = await tool('recolor_look', { slot: 'gnomeland/companion', look: 'agent', to: path.join(appData, 'recolored'), hue: 90 }, 300000);
    check(recolored?.isError === false && fs.existsSync(path.join(appData, 'recolored', 'companion_3.glb')), 'recolor_look writes four companions');
    const colored = await tool('make_character', { model: process.env.STUDIO_SMOKE_MODEL, slot: 'gnomeland/openai', to: path.join(appData, 'colored'), title: 'Colored', hue: 120, tint: '#d04040' }, 300000);
    check(colored?.isError === false && fs.statSync(path.join(appData, 'colored', 'character.glb')).size !== fs.statSync(path.join(to, 'character.glb')).size, 'make_character changes the colors of a model brought to it');
    const listed = (await tool('list_pieces', {}))?.structuredContent?.pieces ?? [];
    check(listed.length === 3 && listed.some((p) => p.piece === made.structuredContent.piece && p.title === 'Smoke' && p.slot === 'gnomeland/openai' && p.folder === to), `list_pieces lists the three pieces made (${listed.map((p) => p.title)})`);
    const removed = await tool('remove_piece', { piece: made.structuredContent.piece });
    const left = (await tool('list_pieces', {}))?.structuredContent?.pieces ?? [];
    check(removed?.isError === false && left.length === 2 && fs.existsSync(path.join(to, 'character.glb')), 'remove_piece takes one piece off the list and leaves its folder');
  }
  check(lines.every((l) => { try { return typeof JSON.parse(l) === 'object'; } catch { return false; } }), 'stdout carries only JSON');
  check(lines.some((l) => l.includes('"code":-32700')), 'a malformed line gets a parse error');
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: nextId++, method: 'tools/call', params: { name: 'list_slots', arguments: {} } }) + '\n');
  child.stdin.end();
  const code = await Promise.race([exited, new Promise((r) => setTimeout(() => r('timeout'), 60000))]);
  check(code === 0, `exits cleanly when stdin closes with a call in flight (exit ${code})`);
} catch (e) {
  check(false, e.message);
  child.kill();
  await exited;
}
if (failures.length) {
  console.log(lines.filter((l) => { try { JSON.parse(l); return false; } catch { return true; } }).slice(0, 10).join('\n'));
  console.log(stderr.split('\n').slice(-30).join('\n'));
  process.exitCode = 1;
}
fs.rmSync(appData, { recursive: true, force: true, maxRetries: 10 });
