import { spawn } from 'child_process';
import os from 'os';

const platform = os.platform(); // 'darwin', 'win32', 'linux'
const arch = os.arch(); // 'arm64', 'x64'

let feature = '';

if (platform === 'darwin') {
  if (arch === 'arm64') {
    feature = 'mac-aarch';
  } else {
    feature = 'mac-x86_64';
  }
} else if (platform === 'win32') {
  feature = 'windows';
} else if (platform === 'linux') {
  feature = 'linux';
} else {
  console.error(`[AutoSubs Dev] Unsupported platform: ${platform}`);
  process.exit(1);
}

const args = ['tauri', 'dev', '--features', feature, '--', '--no-default-features'];
const npxCommand = platform === 'win32' ? 'npx.cmd' : 'npx';

console.log(`[AutoSubs Dev] Platform: ${platform} (${arch})`);
console.log(`[AutoSubs Dev] Command: ${npxCommand} ${args.join(' ')}`);

const child = spawn(npxCommand, args, { stdio: 'inherit' });

child.on('error', (error) => {
  console.error(`[AutoSubs Dev] Failed to start ${npxCommand}: ${error.message}`);
  process.exit(1);
});

child.on('close', (code) => {
  process.exit(code || 0);
});
