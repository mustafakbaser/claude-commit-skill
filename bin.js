#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');

const SKILL_NAME = 'commit';
const home = os.homedir();
const skillDir = path.join(home, '.claude', 'skills', SKILL_NAME);
const packageDir = __dirname;

// Every file the skill ships. Anything not listed here is treated as a leftover
// from an older version and removed, so a renamed or dropped reference file does
// not linger in the install and get read alongside its replacement.
const PAYLOAD = ['SKILL.md', 'references', 'scripts'];

function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src)) {
    const srcPath = path.join(src, entry);
    const destPath = path.join(dest, entry);
    if (fs.statSync(srcPath).isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      copyFile(srcPath, destPath);
    }
  }
}

function copyFile(src, dest) {
  fs.copyFileSync(src, dest);
  // npm does not reliably preserve the executable bit through pack/unpack, and
  // preflight.sh is invoked directly rather than through an interpreter.
  if (dest.endsWith('.sh')) {
    fs.chmodSync(dest, 0o755);
  }
}

function pruneStale(dir, keep) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir)) {
    if (keep.includes(entry)) continue;
    fs.rmSync(path.join(dir, entry), { recursive: true, force: true });
  }
}

function pruneDir(installed, shipped) {
  if (!fs.existsSync(installed)) return;
  const valid = fs.existsSync(shipped) ? fs.readdirSync(shipped) : [];
  pruneStale(installed, valid);
}

console.log('');
console.log('  Installing Claude Code /commit skill...');
console.log('');

try {
  fs.mkdirSync(skillDir, { recursive: true });

  copyFile(path.join(packageDir, 'SKILL.md'), path.join(skillDir, 'SKILL.md'));

  for (const dir of ['references', 'scripts']) {
    const src = path.join(packageDir, dir);
    if (fs.existsSync(src)) {
      copyDir(src, path.join(skillDir, dir));
      pruneDir(path.join(skillDir, dir), src);
    }
  }

  pruneStale(skillDir, PAYLOAD);

  console.log('  Installed to: ' + skillDir);
  console.log('');
  console.log('  Restart Claude Code to activate the /commit command.');
  console.log('');
} catch (err) {
  console.error('  Error:', err.message);
  process.exit(1);
}
