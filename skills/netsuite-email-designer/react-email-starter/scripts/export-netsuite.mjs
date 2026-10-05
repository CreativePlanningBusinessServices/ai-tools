#!/usr/bin/env node
// Runs `email export`, then turns the [[ns:…]] tokens that <NS>/<FreeMarker> emitted back into
// FreeMarker. React escapes quotes and angle brackets in text and attributes, so FreeMarker can't
// be typed into JSX directly; the base64 token survives rendering unchanged.
import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const args = process.argv.slice(2);
const skipExport = args.includes('--no-export');
const outDir = args.find((arg) => !arg.startsWith('--')) ?? 'out';
const TOKEN = /\[\[ns:([A-Za-z0-9+/=]+)\|(wrap|raw)\]\]/g;

const fail = (message) => {
  console.error(`export-netsuite: ${message}`);
  process.exit(1);
};

if (!skipExport) {
  execFileSync('npx', ['email', 'export', '--pretty', '--outDir', outDir], { stdio: 'inherit' });
}

const htmlFiles = readdirSync(outDir).filter((name) => name.endsWith('.html'));
if (htmlFiles.length === 0) fail(`no .html files in ${outDir}`);

for (const name of htmlFiles) {
  const filePath = join(outDir, name);
  const exported = readFileSync(filePath, 'utf8');
  if (exported.includes('${')) {
    fail(`${name}: contains a literal "\${" — use <NS expr="…" /> or ns('…') instead of typing FreeMarker into JSX`);
  }
  const rewritten = exported.replace(TOKEN, (_match, encoded, mode) => {
    const expression = Buffer.from(encoded, 'base64').toString('utf8');
    return mode === 'wrap' ? '${' + expression + '}' : expression;
  });
  if (rewritten.includes('[[ns:')) fail(`${name}: unrecognised token left behind — only <NS>/<FreeMarker> may emit [[ns:…]]`);
  writeFileSync(filePath, rewritten);
  console.log(`netsuite-ready: ${filePath}`);
}
