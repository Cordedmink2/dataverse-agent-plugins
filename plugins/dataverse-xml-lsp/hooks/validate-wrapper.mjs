// PostToolUse gate: auto-run the Dataverse XML validator on the files the live LSP does not cover.
//
// The LSP associates only the authoritative schemas (ribbon, sitemap, fetch, isv.config,
// customizations.xml) by filename. The lag-prone / wrapper types have no live coverage, so we run
// Validate-DataverseXml.ps1 on them post-edit and surface failures to the model (exit 2). The usage
// skill teaches how to read that output (own edits vs OOB noise).
//
// Gate order, cheapest first: no event/path -> 0; not .xml -> 0; root not validator-owned -> 0.
// Exit 0 in those cases is "nothing to do", not a masked error.
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Validator-owned roots the LSP never associates. Case-sensitive: lowercase 'importexportxml'
// (ParameterXml) is distinct from 'ImportExportXml' (customizations.xml, which the LSP owns).
const OWNED_ROOTS = new Set([
  'form', 'forms', 'datadefinition', 'visualization', 'viewers', 'importexportxml',
]);

function rootElement(file) {
  let xml;
  try { xml = readFileSync(file, 'utf8'); } catch { return null; }
  const cleaned = xml
    .replace(/^﻿/, '')
    .replace(/<\?[\s\S]*?\?>/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<!DOCTYPE[^>]*>/gi, '');
  // Dataverse customization roots are unprefixed; a namespaced root (<ns:form>) is not expected.
  const m = cleaned.match(/<([A-Za-z_][\w.-]*)/);
  return m ? m[1] : null;
}

let raw = '';
try { raw = readFileSync(0, 'utf8'); } catch { process.exit(0); }
if (!raw.trim()) process.exit(0);

let evt;
try { evt = JSON.parse(raw); } catch { process.exit(0); }

const file = evt?.tool_input?.file_path;
if (!file || !/\.xml$/i.test(file)) process.exit(0);

const root = rootElement(file);
if (!root || !OWNED_ROOTS.has(root)) process.exit(0);

// hooks/ -> plugin root
const pluginRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const validator = join(pluginRoot, 'scripts', 'Validate-DataverseXml.ps1');
const res = spawnSync('pwsh', ['-NoProfile', '-File', validator, file], { encoding: 'utf8' });

// pwsh missing / spawn failure: can't validate -> don't cry validation-failure.
if (res.error || typeof res.status !== 'number') process.exit(0);
if (res.status === 0) process.exit(0);

const out = [res.stdout, res.stderr].filter(Boolean).join('\n').trim();
process.stderr.write(`Dataverse XML validation failed for ${file}:\n${out}\n`);
process.exit(2);
