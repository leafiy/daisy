const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { downloadArtifact } = require('@electron/get');

const electronRoot = path.join(__dirname, '..', 'node_modules', 'electron');
const electronPackagePath = path.join(electronRoot, 'package.json');

function platformPath() {
  switch (process.platform) {
    case 'darwin':
      return 'Electron.app/Contents/MacOS/Electron';
    case 'linux':
    case 'freebsd':
    case 'openbsd':
      return 'electron';
    case 'win32':
      return 'electron.exe';
    default:
      throw new Error(`Unsupported Electron platform: ${process.platform}`);
  }
}

function ensurePathFile() {
  const relativeExecutable = platformPath();
  const executable = path.join(electronRoot, 'dist', relativeExecutable);
  if (!fs.existsSync(executable)) {
    return false;
  }

  if (process.platform === 'darwin') {
    const framework = path.join(
      electronRoot,
      'dist',
      'Electron.app',
      'Contents',
      'Frameworks',
      'Electron Framework.framework',
      'Electron Framework'
    );
    if (!fs.existsSync(framework)) {
      return false;
    }
  }

  fixExecutableModes();
  fs.writeFileSync(path.join(electronRoot, 'path.txt'), relativeExecutable);

  if (fs.existsSync(electronPackagePath)) {
    const version = require(electronPackagePath).version;
    fs.writeFileSync(path.join(electronRoot, 'dist', 'version'), version);
  }

  return true;
}

function chmodIfExists(file) {
  if (fs.existsSync(file)) {
    fs.chmodSync(file, 0o755);
  }
}

function fixExecutableModes() {
  if (process.platform !== 'darwin') {
    chmodIfExists(path.join(electronRoot, 'dist', platformPath()));
    return;
  }

  const appRoot = path.join(electronRoot, 'dist', 'Electron.app', 'Contents');
  chmodIfExists(path.join(appRoot, 'MacOS', 'Electron'));
  chmodIfExists(
    path.join(
      appRoot,
      'Frameworks',
      'Electron Framework.framework',
      'Versions',
      'A',
      'Electron Framework'
    )
  );

  const frameworks = path.join(appRoot, 'Frameworks');
  if (!fs.existsSync(frameworks)) return;

  for (const entry of fs.readdirSync(frameworks)) {
    if (!entry.endsWith('.app')) continue;
    const macos = path.join(frameworks, entry, 'Contents', 'MacOS');
    if (!fs.existsSync(macos)) continue;

    for (const executable of fs.readdirSync(macos)) {
      chmodIfExists(path.join(macos, executable));
    }
  }
}

if (!fs.existsSync(electronRoot)) {
  throw new Error('Electron is not installed. Run npm install first.');
}

async function installElectron() {
  fs.rmSync(path.join(electronRoot, 'dist'), { recursive: true, force: true });
  fs.rmSync(path.join(electronRoot, 'path.txt'), { force: true });

  const version = require(electronPackagePath).version;
  const zipPath = await downloadArtifact({
    version,
    artifactName: 'electron',
    force: process.env.force_no_cache === 'true',
    checksums: require(path.join(electronRoot, 'checksums.json')),
    platform: process.platform,
    arch: process.arch
  });

  const dist = path.join(electronRoot, 'dist');
  fs.mkdirSync(dist, { recursive: true });

  const extractor = spawnSync('unzip', ['-q', zipPath, '-d', dist], { stdio: 'inherit' });

  if (extractor.status !== 0) {
    process.exit(extractor.status || 1);
  }
}

(async () => {
  if (!ensurePathFile()) {
    await installElectron();

    if (!ensurePathFile()) {
      throw new Error('Electron binary was not found after install.');
    }
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
