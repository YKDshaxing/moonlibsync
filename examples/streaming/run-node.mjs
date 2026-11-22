// SPDX-License-Identifier: LGPL-2.1-or-later
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const buildDir = process.env.MOONLIBSYNC_BUILD_DIR || '_build';
const rebuild = process.argv.includes('--rebuild');
const candidates = [
  path.join(root, buildDir, 'js', 'debug', 'build', 'examples', 'streaming', 'streaming.js'),
  path.join(
    root,
    buildDir,
    'js',
    'debug',
    'build',
    'YKDshaxing',
    'moonlibsync',
    'examples',
    'streaming',
    'streaming.js',
  ),
];

let targetJs = candidates.find((p) => fs.existsSync(p));
if (rebuild || !targetJs) {
  const moonArgs = ['--target-dir', buildDir, 'build', 'examples/streaming', '--target', 'js'];
  const build = spawnSync('moon', moonArgs, {
    cwd: root,
    encoding: 'utf8',
  });
  if (build.stdout) process.stdout.write(build.stdout);
  if (build.stderr) process.stderr.write(build.stderr);
  if (build.error) {
    throw build.error;
  }
  if (build.status !== 0) {
    process.exit(build.status ?? 1);
  }
  targetJs = candidates.find((p) => fs.existsSync(p));
}
if (!targetJs) {
  throw new Error('Compiled streaming.js not found in expected paths: ' + candidates.join(', '));
}

const stdout = execFileSync(process.execPath, [targetJs], {
  cwd: root,
  encoding: 'utf8',
});
process.stdout.write(stdout);

if (!stdout.includes('STREAMING_EXAMPLE_OK')) {
  console.error('Expected STREAMING_EXAMPLE_OK in streaming.js output');
  process.exit(1);
}
