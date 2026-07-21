// End-to-end health check for the flow LSP. Launches the plugin exactly as .lsp.json does — via
// the launcher shim (scripts/lsp-launch.mjs), which spawns vscode-json-language-server and injects
// the bundled schema at runtime. Opens each test fixture under a Workflows/ URI and asserts the
// schema actually fires: valid fixtures yield 0 diagnostics, invalid fixtures yield >= 1.
// Exit 0 = healthy, non-zero = broken install/schema/wiring.
//
// The client here supplies NO schema of its own and answers any workspace/configuration pull that
// reaches it with {} — so a firing schema can only have come from the shim. That both exercises
// the real launch path and proves the shim resolves the schema without any stamped config.
//
// It runs TWO scenarios so the check matches whichever config-delivery path the host uses:
//   push - no `configuration` capability advertised; pulls left unanswered by the client.
//   pull - `configuration` capability advertised; any pull reaching the client answered with {}.
// Both must pass.
//
// Usage: node scripts/lsp-smoke.mjs
import { spawn } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const pluginRoot = resolve(here, '..');
const shim = join(here, 'lsp-launch.mjs');
const fixturesDir = join(pluginRoot, 'tests', 'fixtures');

function loadCases() {
  const cases = [];
  for (const kind of ['valid', 'invalid']) {
    const dir = join(fixturesDir, kind);
    for (const name of readdirSync(dir).filter((f) => f.endsWith('.json'))) {
      cases.push({ kind, name, path: join(dir, name) });
    }
  }
  return cases;
}

// Run every fixture through a freshly-spawned shim under the given config-delivery mode.
// Returns the number of failures.
function runScenario(mode) {
  const advertiseConfig = mode === 'pull';
  const server = spawn(process.execPath, [shim, pluginRoot, '--stdio']);
  const diagnostics = new Map(); // uri -> diagnostics[]
  let buf = Buffer.alloc(0);

  const send = (msg) => {
    const s = JSON.stringify({ jsonrpc: '2.0', ...msg });
    server.stdin.write(`Content-Length: ${Buffer.byteLength(s)}\r\n\r\n${s}`);
  };
  const handle = (msg) => {
    // The shim should intercept workspace/configuration; if one still reaches us, answer {} so the
    // schema can only have come from the shim.
    if (msg.method === 'workspace/configuration') { send({ id: msg.id, result: msg.params.items.map(() => ({})) }); return; }
    if (msg.id !== undefined && msg.method) { send({ id: msg.id, result: null }); return; } // ack other server requests
    if (msg.method === 'textDocument/publishDiagnostics') { diagnostics.set(msg.params.uri, msg.params.diagnostics || []); }
  };
  server.stdout.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      const headerEnd = buf.indexOf('\r\n\r\n');
      if (headerEnd === -1) break;
      const m = buf.slice(0, headerEnd).toString('ascii').match(/Content-Length:\s*(\d+)/i);
      const start = headerEnd + 4;
      if (!m) { buf = buf.slice(start); continue; }
      const len = parseInt(m[1], 10);
      if (buf.length < start + len) break;
      handle(JSON.parse(buf.slice(start, start + len).toString('utf8')));
      buf = buf.slice(start + len);
    }
  });

  const waitFor = (uri, timeoutMs = 4000) => new Promise((res, rej) => {
    const started = Date.now();
    const iv = setInterval(() => {
      if (diagnostics.has(uri)) { clearInterval(iv); res(diagnostics.get(uri)); }
      else if (Date.now() - started > timeoutMs) { clearInterval(iv); rej(new Error(`no diagnostics within ${timeoutMs}ms`)); }
    }, 25);
  });

  return (async () => {
    const capabilities = advertiseConfig
      ? { workspace: { configuration: true, didChangeConfiguration: {} } }
      : { workspace: { didChangeConfiguration: {} } };
    // Deliberately supply NO schema: no initializationOptions.settings, empty didChangeConfiguration.
    send({ id: 1, method: 'initialize', params: { processId: process.pid, rootUri: pathToFileURL(pluginRoot).href, capabilities } });
    await new Promise((r) => setTimeout(r, 300));
    send({ method: 'initialized', params: {} });
    send({ method: 'workspace/didChangeConfiguration', params: { settings: {} } });

    let failures = 0;
    console.log(`\n[${mode}]`);
    for (const c of loadCases()) {
      const text = readFileSync(c.path, 'utf8');
      // Synthetic Workflows/ URI so the schema's fileMatch applies regardless of the fixture's real path.
      const uri = pathToFileURL(join(pluginRoot, 'Workflows', `${mode}-${c.kind}-${c.name}`)).href;
      send({ method: 'textDocument/didOpen', params: { textDocument: { uri, languageId: 'json', version: 1, text } } });
      let diags;
      try { diags = await waitFor(uri); }
      catch (e) { console.error(`  ERROR ${c.kind}/${c.name}: ${e.message}`); failures++; continue; }
      const ok = c.kind === 'valid' ? diags.length === 0 : diags.length > 0;
      const detail = diags.length ? ` (${diags[0].message})` : '';
      console.log(`  ${ok ? 'PASS' : 'FAIL'} ${c.kind}/${c.name} -> ${diags.length} diagnostic(s)${ok ? '' : detail}`);
      if (!ok) failures++;
    }
    server.kill();
    return failures;
  })();
}

async function main() {
  if (!loadCases().length) { console.error('No fixtures found under', fixturesDir); process.exit(3); }
  let failures = 0;
  for (const mode of ['push', 'pull']) failures += await runScenario(mode);
  if (failures) { console.error(`\nLSP smoke: ${failures} case(s) failed.`); process.exit(1); }
  console.log('\nLSP smoke: all cases passed (push + pull).');
  process.exit(0);
}

main().catch((e) => { console.error(e); process.exit(2); });
