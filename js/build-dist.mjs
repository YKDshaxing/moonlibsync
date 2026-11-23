// SPDX-License-Identifier: LGPL-2.1-or-later
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createClient } from './index.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const buildDir = process.env.MOONLIBSYNC_BUILD_DIR || '_build';
const resolvedBuildDir = path.resolve(root, buildDir);
const outFile = path.join(here, 'moonlibsync-core.js');

if (process.argv.includes('--clean')) {
  if (fs.existsSync(outFile)) {
    fs.unlinkSync(outFile);
    console.log('Removed js/moonlibsync-core.js');
  }
  process.exit(0);
}

const candidates = [
  path.join(
    resolvedBuildDir,
    'js',
    'release',
    'build',
    'examples',
    'web-demo',
    'web-demo.js',
  ),
  path.join(
    resolvedBuildDir,
    'js',
    'release',
    'build',
    'YKDshaxing',
    'moonlibsync',
    'examples',
    'web-demo',
    'web-demo.js',
  ),
];

if (!process.argv.includes('--no-build')) {
  const args = [
    '--target-dir',
    buildDir,
    'build',
    'examples/web-demo',
    '--target',
    'js',
    '--release',
  ];
  const result = spawnSync('moon', args, {
    cwd: root,
    encoding: 'utf8',
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) {
    throw new Error(`Failed to invoke moon CLI: ${result.error.message}`);
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

const sourceBundle = candidates.find((candidate) => fs.existsSync(candidate));
if (!sourceBundle) {
  const relCandidates = candidates.map((c) => path.relative(root, c).replaceAll('\\', '/'));
  throw new Error(
    `Compiled release bundle web-demo.js not found in: ${relCandidates.join(', ')}`,
  );
}

fs.copyFileSync(sourceBundle, outFile);
try {
  const mod = await import(`${pathToFileURL(outFile).href}?t=${Date.now()}`);
  createClient(mod);
} catch (err) {
  if (fs.existsSync(outFile)) {
    fs.unlinkSync(outFile);
  }
  throw err;
}

const stat = fs.statSync(outFile);
const relSource = path.relative(root, sourceBundle).replaceAll('\\', '/');
console.log(
  `Built js/moonlibsync-core.js (${stat.size} bytes, 37 exports verified) from ${relSource}`,
);
