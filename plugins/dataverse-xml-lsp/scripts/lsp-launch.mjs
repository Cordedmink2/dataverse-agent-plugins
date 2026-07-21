// Launcher shim for the lemminx (XML) native language server.
//
// Claude Code substitutes ${CLAUDE_PLUGIN_ROOT} in .lsp.json command/args (NOT in settings), so
// the plugin root arrives here as an argv. We spawn the platform-specific lemminx binary, proxy
// LSP stdio, and inject xml.fileAssociations (each systemId an absolute file:// url to the right
// XSD) at runtime. Nothing machine-local is ever written to a committed file.
//
// The associations must be injected in THREE places or lemminx silently stops validating:
//   1. the forwarded `initialize` (initializationOptions.settings.xml),
//   2. every client workspace/didChangeConfiguration (an empty client push otherwise CLEARS it),
//   3. by directly answering the server's workspace/configuration pull.
//
// Usage: node lsp-launch.mjs <pluginRoot> [--stdio]
import { spawn } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const pluginRoot = process.argv[2];
if (!pluginRoot) throw new Error('lsp-launch: missing plugin root argument');

// Schema version is pinned in versions.json (same source Get-Schemas.ps1 extracts to). Fail loud
// if the schema dir is missing (e.g. a bad version bump or partial fetch): lemminx would otherwise
// launch and silently validate nothing.
const version = JSON.parse(readFileSync(join(pluginRoot, 'versions.json'), 'utf8')).schemaVersion;
const schemaDir = join(pluginRoot, 'schemas', version);
if (!existsSync(schemaDir)) throw new Error(`lsp-launch: schema dir not found: ${schemaDir}. Run scripts/Get-Schemas.ps1.`);

// lemminx ships under a per-OS binary name (lemminx-win32.exe, lemminx-linux-x86_64,
// lemminx-osx-aarch_64, ...). Get-Lemminx.ps1 installs exactly one; discover it the same way
// rather than guessing the platform suffix here.
const binDir = join(pluginRoot, 'bin');
const bins = readdirSync(binDir).filter((f) => f.startsWith('lemminx'));
if (bins.length !== 1) throw new Error(`lsp-launch: expected exactly one lemminx binary in ${binDir}, found ${bins.length}. Run scripts/Get-Lemminx.ps1.`);
const serverExe = join(binDir, bins[0]);

// pattern -> XSD filename. Charts have no association on purpose (see Set-LspSchemaPaths.ps1).
const assoc = {
  '**/RibbonDiff.xml': 'RibbonCore.xsd',
  '**/[Cc]ustomizations.xml': 'CustomizationsSolution.xsd',
  '**/SiteMap*.xml': 'SiteMap.xsd',
  '**/FormXml/**/*.xml': 'FormXml.xsd',
  '**/SavedQueries/**/*.xml': 'Fetch.xsd',
  '**/*.fetchxml': 'Fetch.xsd',
  '**/isv.config.xml': 'isv.config.xsd',
};
// Every XSD an association points at must exist - a partial extraction would otherwise leave
// lemminx unable to load a schema with no visible error.
const missingXsds = [...new Set(Object.values(assoc))].filter((xsd) => !existsSync(join(schemaDir, xsd)));
if (missingXsds.length) throw new Error(`lsp-launch: missing XSD(s) in ${schemaDir}: ${missingXsds.join(', ')}. Run scripts/Get-Schemas.ps1.`);

const xmlSettings = {
  validation: { enabled: true, schema: { enabled: 'always' } },
  fileAssociations: Object.entries(assoc).map(([pattern, xsd]) => ({
    pattern,
    systemId: pathToFileURL(join(schemaDir, xsd)).href,
  })),
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

const server = spawn(serverExe, [], { stdio: ['pipe', 'pipe', 'inherit'] });

const fromClient = makeParser((msg) => {
  if (msg.method === 'initialize') {
    msg.params = msg.params || {};
    const io = msg.params.initializationOptions = msg.params.initializationOptions || {};
    io.settings = io.settings || {};
    io.settings.xml = xmlSettings;
  }
  if (msg.method === 'workspace/didChangeConfiguration') {
    msg.params = msg.params || {};
    msg.params.settings = msg.params.settings || {};
    msg.params.settings.xml = xmlSettings;
  }
  writeMsg(server.stdin, msg);
});

const fromServer = makeParser((msg) => {
  if (msg.method === 'workspace/configuration' && msg.id !== undefined) {
    const result = (msg.params.items || []).map((it) => (!it.section || it.section === 'xml' ? xmlSettings : {}));
    writeMsg(server.stdin, { jsonrpc: '2.0', id: msg.id, result });
    return; // consumed by the shim; never reaches the client
  }
  writeMsg(process.stdout, msg);
});

process.stdin.on('data', fromClient);
server.stdout.on('data', fromServer);
server.on('error', (err) => { console.error(`lsp-launch: failed to spawn ${serverExe}: ${err.message}`); process.exit(1); });
// Exit on 'close' (fires after stdio has fully drained), not 'exit', so the last forwarded
// message is not truncated.
server.on('close', (c) => process.exit(c ?? 0));
