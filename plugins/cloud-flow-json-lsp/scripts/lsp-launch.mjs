// Launcher shim for the cloud-flow JSON language server.
//
// Claude Code substitutes ${CLAUDE_PLUGIN_ROOT} in .lsp.json command/args (NOT in settings), so
// the plugin root arrives here as an argv. We spawn the real json-language-server, proxy LSP
// stdio, and inject the bundled schema association at runtime — computing an absolute file:// url
// from the passed root. Nothing machine-local is ever written to a committed file.
//
// The schema must be injected in THREE places or the server silently stops validating:
//   1. the forwarded `initialize` (initializationOptions.settings.json),
//   2. every client workspace/didChangeConfiguration (an empty client push otherwise CLEARS it),
//   3. by directly answering the server's workspace/configuration pull.
//
// Usage: node lsp-launch.mjs <pluginRoot> [--stdio]
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const pluginRoot = process.argv[2];
if (!pluginRoot) throw new Error('lsp-launch: missing plugin root argument');

const serverEntry = join(pluginRoot, 'node_modules', 'vscode-langservers-extracted', 'lib', 'json-language-server', 'node', 'jsonServerMain.js');

// Fail loud if the bundled schema is missing (e.g. a partial install): the server would otherwise
// launch and silently validate nothing.
const schemaPath = join(pluginRoot, 'schemas', 'cloud-flow-clientdata.schema.json');
if (!existsSync(schemaPath)) throw new Error(`lsp-launch: schema not found: ${schemaPath}. Run scripts/Install-Plugin.ps1.`);
const schemaUrl = pathToFileURL(schemaPath).href;

const jsonSettings = {
  validate: { enable: true },
  schemas: [{
    fileMatch: ['**/Workflows/*.json', '**/Workflows/**/*.json', '**/*.flow.json'],
    url: schemaUrl,
  }],
};

// --- LSP stdio framing ---
function writeMsg(stream, obj) {
  const s = JSON.stringify(obj);
  stream.write(`Content-Length: ${Buffer.byteLength(s)}\r\n\r\n${s}`);
}
function makeParser(onMsg) {
  let buf = Buffer.alloc(0);
  return (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      const he = buf.indexOf('\r\n\r\n');
      if (he === -1) break;
      const m = buf.slice(0, he).toString('ascii').match(/Content-Length:\s*(\d+)/i);
      const start = he + 4;
      if (!m) { buf = buf.slice(start); continue; }
      const len = parseInt(m[1], 10);
      if (buf.length < start + len) break;
      onMsg(JSON.parse(buf.slice(start, start + len).toString('utf8')));
      buf = buf.slice(start + len);
    }
  };
}

const server = spawn(process.execPath, [serverEntry, '--stdio'], { stdio: ['pipe', 'pipe', 'inherit'] });

const fromClient = makeParser((msg) => {
  if (msg.method === 'initialize') {
    msg.params = msg.params || {};
    const io = msg.params.initializationOptions = msg.params.initializationOptions || {};
    io.provideFormatter = true;
    io.handledSchemaProtocols = ['file'];
    io.settings = io.settings || {};
    io.settings.json = jsonSettings;
  }
  if (msg.method === 'workspace/didChangeConfiguration') {
    msg.params = msg.params || {};
    msg.params.settings = msg.params.settings || {};
    msg.params.settings.json = jsonSettings;
  }
  writeMsg(server.stdin, msg);
});

const fromServer = makeParser((msg) => {
  if (msg.method === 'workspace/configuration' && msg.id !== undefined) {
    const result = (msg.params.items || []).map((it) => (it.section === 'json' ? jsonSettings : {}));
    writeMsg(server.stdin, { jsonrpc: '2.0', id: msg.id, result });
    return; // consumed by the shim; never reaches the client
  }
  writeMsg(process.stdout, msg);
});

process.stdin.on('data', fromClient);
server.stdout.on('data', fromServer);
server.on('error', (err) => { console.error(`lsp-launch: failed to spawn ${serverEntry}: ${err.message}`); process.exit(1); });
// Exit on 'close' (fires after stdio has fully drained), not 'exit', so the last forwarded
// message is not truncated.
server.on('close', (c) => process.exit(c ?? 0));
