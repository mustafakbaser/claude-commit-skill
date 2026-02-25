#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');

const SKILL_NAME = 'commit';
const home = os.homedir();
const skillDir = path.join(home, '.claude', 'skills', SKILL_NAME);
const packageDir = __dirname;

function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src)) {
    const srcPath = path.join(src, entry);
    const destPath = path.join(dest, entry);
    if (fs.statSync(srcPath).isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

console.log('');
console.log('  Installing Claude Code /commit skill...');
console.log('');

try {
  fs.mkdirSync(skillDir, { recursive: true });

  fs.copyFileSync(
    path.join(packageDir, 'SKILL.md'),
    path.join(skillDir, 'SKILL.md')
  );

  const refsDir = path.join(packageDir, 'references');
  if (fs.existsSync(refsDir)) {
    copyDir(refsDir, path.join(skillDir, 'references'));
  }

  console.log('  Installed to: ' + skillDir);
  console.log('');
  console.log('  Restart Claude Code to activate the /commit command.');
  console.log('');
} catch (err) {
  console.error('  Error:', err.message);
  process.exit(1);
}
