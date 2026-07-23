import { spawnSync } from 'node:child_process';
import { copyFileSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const appDir = path.resolve(scriptDir, '..');
const repoRoot = path.resolve(appDir, '..');
const pkg = JSON.parse(readFileSync(path.join(appDir, 'package.json'), 'utf8'));
const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').replace('T', '-');
const releaseName = process.env.RELEASE_NAME || `TaskMasterPro-Next-v${pkg.version}-${stamp}`;
const releaseDir = path.join(appDir, 'releases', releaseName);
const webReleaseDir = path.join(releaseDir, 'web');
const docsDir = path.join(repoRoot, 'docs');

function run(command, args, options = {}) {
  console.log(`\n> ${command} ${args.join(' ')}`);
  let executable = command;
  let finalArgs = args;
  if (process.platform === 'win32') {
    if (command === 'npm' || command === 'npx') {
      const resolved = resolveWindowsExecutable(`${command}.cmd`) ?? `${command}.cmd`;
      executable = 'cmd.exe';
      finalArgs = ['/d', '/c', resolved, ...args];
    } else if (command.toLowerCase().endsWith('.bat') || command.toLowerCase().endsWith('.cmd')) {
      executable = 'cmd.exe';
      finalArgs = ['/d', '/c', command, ...args];
    }
    if (executable !== 'cmd.exe') {
      executable = resolveWindowsExecutable(executable) ?? executable;
    }
  }
  const result = spawnSync(executable, finalArgs, {
    cwd: options.cwd ?? appDir,
    shell: false,
    stdio: 'inherit',
    env: { ...process.env, ...(options.env ?? {}) },
  });
  if (result.status !== 0) {
    if (result.error) {
      throw result.error;
    }
    throw new Error(`${command} ${args.join(' ')} failed with exit code ${result.status}`);
  }
}

function runNodeScript(script, args, options = {}) {
  run(process.execPath, [script, ...args], options);
}

function resolveWindowsExecutable(command) {
  if (path.isAbsolute(command) && existsSync(command)) return command;
  const pathDirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  const extensions = path.extname(command) ? [''] : ['.cmd', '.bat', '.exe', ''];
  for (const dir of pathDirs) {
    for (const extension of extensions) {
      const candidate = path.join(dir, `${command}${extension}`);
      if (existsSync(candidate)) return candidate;
    }
  }
  return undefined;
}

function ensureCleanDir(dir) {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function removeNonMarkdownContents(dir) {
  mkdirSync(dir, { recursive: true });
  for (const name of readdirSync(dir)) {
    const entry = path.join(dir, name);
    const stat = statSync(entry);
    if (stat.isDirectory()) {
      rmSync(entry, { recursive: true, force: true });
      continue;
    }
    if (!name.toLowerCase().endsWith('.md')) {
      rmSync(entry, { force: true });
    }
  }
}

function findFirstFile(dir, predicate) {
  if (!existsSync(dir)) return undefined;
  for (const name of readdirSync(dir)) {
    const entry = path.join(dir, name);
    const stat = statSync(entry);
    if (stat.isDirectory()) {
      const found = findFirstFile(entry, predicate);
      if (found) return found;
    } else if (predicate(entry)) {
      return entry;
    }
  }
  return undefined;
}

function findAndroidSdk() {
  const candidates = [
    process.env.ANDROID_HOME,
    process.env.ANDROID_SDK_ROOT,
    path.join(process.env.LOCALAPPDATA || '', 'Android', 'Sdk'),
  ].filter(Boolean);
  return candidates.find((candidate) => existsSync(candidate));
}

function latestBuildToolsDir(androidSdk) {
  const buildTools = path.join(androidSdk, 'build-tools');
  if (!existsSync(buildTools)) return undefined;
  const versions = readdirSync(buildTools).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  return versions.length ? path.join(buildTools, versions.at(-1)) : undefined;
}

function ensureDebugKeystore() {
  const androidHome = path.join(homedir(), '.android');
  const keystore = path.join(androidHome, 'debug.keystore');
  if (existsSync(keystore)) return keystore;
  mkdirSync(androidHome, { recursive: true });
  run('keytool', [
    '-genkeypair',
    '-v',
    '-keystore',
    keystore,
    '-storepass',
    'android',
    '-alias',
    'androiddebugkey',
    '-keypass',
    'android',
    '-keyalg',
    'RSA',
    '-keysize',
    '2048',
    '-validity',
    '10000',
    '-dname',
    'CN=Android Debug,O=Android,C=US',
  ]);
  return keystore;
}

function copySupabaseSql() {
  const preferred = path.join(repoRoot, 'release', 'TaskMasterPro-supabase-clean-rebuild.sql');
  const fallback = path.join(repoRoot, 'supabase', 'taskmaster_clean_rebuild.sql');
  const source = existsSync(preferred) ? preferred : fallback;
  if (!existsSync(source)) {
    throw new Error(`Clean Supabase rebuild SQL was not found at ${preferred} or ${fallback}`);
  }
  const target = path.join(releaseDir, 'TaskMasterPro-Next-Supabase-Clean-Rebuild.sql');
  copyFileSync(source, target);
  return target;
}

function syncMediaAssets() {
  runNodeScript(path.join(scriptDir, 'sync-assets.mjs'), []);
}

function packageWeb() {
  syncMediaAssets();
  runNodeScript(path.join(appDir, 'node_modules', 'typescript', 'bin', 'tsc'), ['--noEmit']);
  runNodeScript(path.join(appDir, 'node_modules', 'vite', 'bin', 'vite.js'), ['build']);
  cpSync(path.join(appDir, 'dist'), webReleaseDir, { recursive: true });
  removeNonMarkdownContents(docsDir);
  cpSync(path.join(appDir, 'dist'), docsDir, { recursive: true });
  copyFileSync(path.join(appDir, 'dist', 'index.html'), path.join(docsDir, '404.html'));
}

function packageElectron() {
  const outputDir = path.join(tmpdir(), `${releaseName}-electron-output`);
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    rmSync(outputDir, { recursive: true, force: true });
    try {
      runNodeScript(path.join(appDir, 'node_modules', 'electron-builder', 'cli.js'), [
        '--win',
        'nsis',
        '--publish',
        'never',
        '--config.directories.output',
        outputDir,
      ]);
      lastError = undefined;
      break;
    } catch (error) {
      lastError = error;
      if (attempt === 3) break;
      console.warn(`Electron packaging failed on attempt ${attempt}; retrying after Windows releases the build files.`);
      sleep(2500 * attempt);
    }
  }
  if (lastError) throw lastError;
  const installer = findFirstFile(outputDir, (file) => file.toLowerCase().endsWith('.exe') && !file.toLowerCase().includes('uninstaller'));
  if (!installer) throw new Error(`Electron installer was not produced in ${outputDir}`);
  const stableTarget = path.join(releaseDir, 'TaskMasterPro-Next-Windows-Setup.exe');
  copyFileSync(installer, stableTarget);
  rmSync(outputDir, { recursive: true, force: true });
  return stableTarget;
}

function packageAndroid() {
  const androidDir = path.join(appDir, 'android');
  if (!existsSync(androidDir)) {
    runNodeScript(path.join(appDir, 'node_modules', '@capacitor', 'cli', 'bin', 'capacitor'), ['add', 'android']);
  }
  runNodeScript(path.join(appDir, 'node_modules', '@capacitor', 'cli', 'bin', 'capacitor'), ['sync', 'android']);
  syncMediaAssets();

  const androidSdk = findAndroidSdk();
  if (!androidSdk) {
    throw new Error('Android SDK was not found. Set ANDROID_HOME or ANDROID_SDK_ROOT.');
  }
  writeFileSync(
    path.join(androidDir, 'local.properties'),
    `sdk.dir=${androidSdk.replace(/\\/g, '\\\\')}\n`,
  );

  const gradlew = process.platform === 'win32' ? 'gradlew.bat' : './gradlew';
  run(path.join(androidDir, gradlew), ['assembleRelease'], {
    cwd: androidDir,
    env: {
      ANDROID_HOME: androidSdk,
      ANDROID_SDK_ROOT: androidSdk,
    },
  });

  const apkDir = path.join(androidDir, 'app', 'build', 'outputs', 'apk', 'release');
  const signedRelease = findFirstFile(apkDir, (file) => file.endsWith('.apk') && !file.includes('unsigned'));
  const unsignedRelease = findFirstFile(apkDir, (file) => file.endsWith('.apk') && file.includes('unsigned'));
  const finalApk = path.join(releaseDir, 'TaskMasterPro-Next-Android.apk');

  if (signedRelease) {
    copyFileSync(signedRelease, finalApk);
    return finalApk;
  }
  if (!unsignedRelease) {
    throw new Error(`No release APK was produced in ${apkDir}`);
  }

  const buildTools = latestBuildToolsDir(androidSdk);
  const apksigner = buildTools
    ? path.join(buildTools, process.platform === 'win32' ? 'apksigner.bat' : 'apksigner')
    : undefined;
  if (!apksigner || !existsSync(apksigner)) {
    throw new Error('apksigner was not found in Android SDK build-tools.');
  }
  const keystore = ensureDebugKeystore();
  run(apksigner, [
    'sign',
    '--ks',
    keystore,
    '--ks-pass',
    'pass:android',
    '--key-pass',
    'pass:android',
    '--out',
    finalApk,
    unsignedRelease,
  ]);
  return finalApk;
}

function main() {
  ensureCleanDir(releaseDir);
  packageWeb();
  const windowsInstaller = packageElectron();
  const androidApk = packageAndroid();
  const supabaseSql = copySupabaseSql();

  const manifest = {
    releaseName,
    version: pkg.version,
    createdAt: new Date().toISOString(),
    web: path.relative(releaseDir, webReleaseDir),
    windowsInstaller: path.basename(windowsInstaller),
    androidApk: path.basename(androidApk),
    supabaseSql: path.basename(supabaseSql),
  };
  writeFileSync(path.join(releaseDir, 'release-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log('\nRelease package complete:');
  console.log(releaseDir);
  console.log(JSON.stringify(manifest, null, 2));
}

main();
