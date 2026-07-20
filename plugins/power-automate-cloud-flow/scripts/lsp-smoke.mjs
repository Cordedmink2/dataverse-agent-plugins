// End-to-end health check for the flow LSP: launches vscode-json-language-server exactly as
// .lsp.json does, feeds it the schema association the plugin ships, opens each test fixture under
// a Workflows/ URI, and asserts the schema actually fires — valid fixtures yield 0 diagnostics,
// invalid fixtures yield >= 1. Exit 0 = healthy, non-zero = broken install/schema/wiring.
//
// It runs TWO scenarios so the check matches Claude Code's real mechanism, which is not fully
// documented for the workspace/configuration pull:
//   push - schemas provided ONLY via initializationOptions + workspace/didChangeConfiguration,
//          with NO configuration capability advertised and pulls left unanswered. This is what
//          the Claude Code docs describe ("settings passed via workspace/didChangeConfiguration").
//   pull - configuration capability advertised and the server's workspace/configuration request
//          answered. The alternative path some clients use.
// Both must pass, so the plugin works regardless of which path the host actually uses.
//
// Usage: node scripts/lsp-smoke.mjs
import { spawn } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const pluginRoot = resolve(here, '..');
const serverEntry = join(pluginRoot, 'node_modules', 'vscode-langservers-extracted', 'lib', 'json-language-server', 'node', 'jsonServerMain.js');
const schemaUri = pathToFileURL(join(pluginRoot, 'schemas', 'cloud-flow-clientdata.schema.json')).href;
const fixturesDir = join(pluginRoot, 'tests', 'fixtures');

// The schema settings the client hands the server (mirrors .lsp.json settings.json).
const jsonSettings = {
  validate: { enable: true },
  schemas: [{ fileMatch: ['**/Workflows/*.json', '**/Workflows/**/*.json', '**/*.flow.json'], url: schemaUri }],
};
// initializationOptions mirrors .lsp.json: handledSchemaProtocols lets the server load file:// schemas.
const initOptions = { provideFormatter: true, handledSchemaProtocols: ['file'], settings: { json: jsonSettings } };

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

// Run every fixture through a freshly-spawned server under the given config-delivery mode.
// Returns the number of failures.
function runScenario(mode) {
  const answerPulls = mode === 'pull';
  const server = spawn(process.execPath, [serverEntry, '--stdio']);
  const diagnostics = new Map(); // uri -> diagnostics[]
  let buf = Buffer.alloc(0);

  const send = (msg) => {
    const s = JSON.stringify({ jsonrpc: '2.0', ...msg });
    server.stdin.write(`Content-Length: ${Buffer.byteLength(s)}\r\n\r\n${s}`);
  };
  const handle = (msg) => {
    if (msg.method === 'workspace/configuration') {
      // In push mode, simulate a host that does NOT supply config via pull (empty results),
      // proving the schema still arrives via initializationOptions + didChangeConfiguration.
      const result = msg.params.items.map((it) => (answerPulls && it.section === 'json' ? jsonSettings : {}));
      send({ id: msg.id, result });
      return;
    }
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
    const capabilities = answerPulls
      ? { workspace: { configuration: true, didChangeConfiguration: {} } }
      : { workspace: { didChangeConfiguration: {} } }; // no `configuration` -> push model
    send({ id: 1, method: 'initialize', params: { processId: process.pid, rootUri: pathToFileURL(pluginRoot).href, initializationOptions: initOptions, capabilities } });
    await new Promise((r) => setTimeout(r, 300));
    send({ method: 'initialized', params: {} });
    send({ method: 'workspace/didChangeConfiguration', params: { settings: { json: jsonSettings } } });

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
