// End-to-end health check for the XML LSP. Launches the plugin exactly as .lsp.json does — via
// the launcher shim (scripts/lsp-launch.mjs), which spawns the lemminx binary and injects the
// xml.fileAssociations at runtime. Opens a ribbon fixture under a **/RibbonDiff.xml URI and
// asserts the schema actually fires: the valid fixture yields 0 diagnostics, the invalid one >= 1.
// Exit 0 = healthy, non-zero = broken install/schema/wiring.
//
// The client here supplies NO schema of its own and answers any workspace/configuration pull that
// reaches it with {} — so a firing schema can only have come from the shim. That both exercises
// the real launch path and proves the shim resolves the associations without any stamped config.
//
// It runs TWO scenarios so the check matches whichever config-delivery path the host uses:
//   push - no `configuration` capability advertised; pulls left unanswered by the client.
//   pull - `configuration` capability advertised; any pull reaching the client answered with {}.
// Both must pass.
//
// Usage: node scripts/lsp-smoke.mjs
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const pluginRoot = resolve(here, '..');
const shim = join(here, 'lsp-launch.mjs');
const fixturesDir = join(pluginRoot, 'tests', 'fixtures');

// Ribbon is the fully-authoritative fragment (RibbonCore.xsd). The synthetic URI name RibbonDiff.xml
// makes the shim's **/RibbonDiff.xml association apply regardless of the fixture's real filename.
const cases = [
  { kind: 'valid', path: join(fixturesDir, 'valid', 'ribbon.xml') },
  { kind: 'invalid', path: join(fixturesDir, 'invalid', 'ribbon.xml') },
];

// Run every case through a freshly-spawned shim under the given config-delivery mode.
// Returns the number of failures.
function runScenario(mode) {
  const advertiseConfig = mode === 'pull';
  const server = spawn(process.execPath, [shim, pluginRoot, '--stdio']);
  const diagnostics = new Map(); // uri -> diagnostics[]
  const lastUpdate = new Map(); // uri -> timestamp of most recent publish
  let buf = Buffer.alloc(0);

  const send = (msg) => {
    const s = JSON.stringify({ jsonrpc: '2.0', ...msg });
    server.stdin.write(`Content-Length: ${Buffer.byteLength(s)}\r\n\r\n${s}`);
  };
  const handle = (msg) => {
    // The shim should intercept workspace/configuration; if one still reaches us, answer {} so the
    // associations can only have come from the shim.
    if (msg.method === 'workspace/configuration') { send({ id: msg.id, result: (msg.params.items || []).map(() => ({})) }); return; }
    if (msg.id !== undefined && msg.method) { send({ id: msg.id, result: null }); return; } // ack other server requests
    if (msg.method === 'textDocument/publishDiagnostics') {
      diagnostics.set(msg.params.uri, msg.params.diagnostics || []);
      lastUpdate.set(msg.params.uri, Date.now());
    }
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

  // lemminx publishes a transient "No grammar constraints" diagnostic the instant a doc opens, then
  // RE-publishes after the injected fileAssociations settle (schema applied). We must read the
  // settled result, not that first transient: wait until at least one publish has arrived AND no
  // further publish has landed for `quietMs`. Fail loud if none ever arrives.
  const waitSettled = (uri, quietMs = 1200, timeoutMs = 20000) => new Promise((res, rej) => {
    const started = Date.now();
    const iv = setInterval(() => {
      const seen = diagnostics.has(uri);
      if (seen && Date.now() - lastUpdate.get(uri) >= quietMs) { clearInterval(iv); res(diagnostics.get(uri)); }
      else if (Date.now() - started > timeoutMs) {
        clearInterval(iv);
        if (seen) res(diagnostics.get(uri)); else rej(new Error(`no diagnostics within ${timeoutMs}ms`));
      }
    }, 25);
  });

  return (async () => {
    const capabilities = advertiseConfig
      ? { workspace: { configuration: true, didChangeConfiguration: {} } }
      : { workspace: { didChangeConfiguration: {} } };
    // Deliberately supply NO schema: no initializationOptions.settings, empty didChangeConfiguration.
    send({ id: 1, method: 'initialize', params: { processId: process.pid, rootUri: pathToFileURL(pluginRoot).href, capabilities } });
    await new Promise((r) => setTimeout(r, 500));
    send({ method: 'initialized', params: {} });
    send({ method: 'workspace/didChangeConfiguration', params: { settings: {} } });
    // Let the shim-injected config land before opening any doc. lemminx validates a doc at open
    // time; if it opens before the fileAssociations are in effect it reports "No grammar
    // constraints" and does not necessarily re-fire. A host configures the server, then opens files.
    await new Promise((r) => setTimeout(r, 1500));

    let failures = 0;
    console.log(`\n[${mode}]`);
    for (const c of cases) {
      const text = readFileSync(c.path, 'utf8');
      // Synthetic URI whose FILENAME is exactly RibbonDiff.xml so the shim's **/RibbonDiff.xml
      // association applies regardless of the fixture's real filename. The glob matches on the last
      // path segment, so uniqueness comes from the parent dir (mode/kind), never the filename.
      const uri = pathToFileURL(join(pluginRoot, 'src', mode, c.kind, 'RibbonDiff.xml')).href;
      send({ method: 'textDocument/didOpen', params: { textDocument: { uri, languageId: 'xml', version: 1, text } } });
      let diags;
      try { diags = await waitSettled(uri); }
      catch (e) { console.error(`  ERROR ${c.kind}/ribbon.xml: ${e.message}`); failures++; continue; }
      const ok = c.kind === 'valid' ? diags.length === 0 : diags.length > 0;
      const detail = diags.length ? ` (${diags[0].message})` : '';
      console.log(`  ${ok ? 'PASS' : 'FAIL'} ${c.kind}/ribbon.xml -> ${diags.length} diagnostic(s)${ok ? '' : detail}`);
      if (!ok) failures++;
    }
    server.kill();
    return failures;
  })();
}

async function main() {
  let failures = 0;
  for (const mode of ['push', 'pull']) failures += await runScenario(mode);
  if (failures) { console.error(`\nXML LSP smoke: ${failures} case(s) failed.`); process.exit(1); }
  console.log('\nXML LSP smoke: all cases passed (push + pull).');
  process.exit(0);
}

main().catch((e) => { console.error(e); process.exit(2); });
