import { copyFileSync, existsSync, mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import pngToIco from 'png-to-ico';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const appDir = path.resolve(scriptDir, '..');
const repoRoot = path.resolve(appDir, '..');
const mediaDir = path.join(repoRoot, 'media');

const logoDir = path.join(mediaDir, 'app-logo');
const soundDir = path.join(mediaDir, 'notifications-sound');
const publicAssetsDir = path.join(appDir, 'public', 'assets');
const publicBrandingDir = path.join(publicAssetsDir, 'branding');
const publicIconsDir = path.join(publicAssetsDir, 'icons');
const publicSoundsDir = path.join(publicAssetsDir, 'sounds');
const resourcesDir = path.join(appDir, 'resources');
const resourcesAssetDir = path.join(resourcesDir, 'assets');
const resourcesIconDir = path.join(resourcesDir, 'icons');
const resourcesSoundDir = path.join(resourcesDir, 'sounds');

const logos = {
  dark: 'TaskMaster_Pro_Blue_Dark_Transparent.png',
  blackGold: 'TaskMaster_Pro_Black_Gold_Transparent_main-logo.png',
  light: 'TaskMaster_Pro_Light_Transparent.png',
};

const sounds = {
  focusCompleted: 'app-alarm.mp3',
  breakCompleted: 'done-sound.mp3',
  taskReminder: 'app-notifications.mp3',
  taskOverdue: 'alert-sound.mp3',
  dailyCoaching: 'UI-notification-tone.mp3',
  criticalAlarm: 'notifications.mp3',
  click: 'click-sound.mp3',
};

function ensureDir(dir) {
  mkdirSync(dir, { recursive: true });
}

function requireFile(file) {
  if (!existsSync(file)) {
    throw new Error(`Required media asset is missing: ${file}`);
  }
}

function normalizedAndroidName(name) {
  return name
    .replace(/\.[^.]+$/, '')
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .replace(/[^a-zA-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .toLowerCase();
}

async function renderIcon(source, target, size) {
  await sharp(source)
    .resize(size, size, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toFile(target);
}

async function sync() {
  for (const dir of [
    publicBrandingDir,
    publicIconsDir,
    publicSoundsDir,
    resourcesAssetDir,
    resourcesIconDir,
    resourcesSoundDir,
  ]) {
    ensureDir(dir);
  }

  const logoManifest = {};
  for (const [key, filename] of Object.entries(logos)) {
    const source = path.join(logoDir, filename);
    requireFile(source);
    const publicName = `logo-${key.replace(/[A-Z]/g, (value) => `-${value.toLowerCase()}`)}.png`;
    const publicTarget = path.join(publicBrandingDir, publicName);
    copyFileSync(source, publicTarget);
    copyFileSync(source, path.join(resourcesAssetDir, publicName));
    logoManifest[key] = `assets/branding/${publicName}`;
  }
  copyFileSync(path.join(logoDir, logos.dark), path.join(publicAssetsDir, 'taskmaster-logo.png'));
  copyFileSync(path.join(logoDir, logos.dark), path.join(resourcesAssetDir, 'taskmaster-logo.png'));

  const iconSource = path.join(logoDir, logos.dark);
  const iconPngs = [];
  for (const size of [16, 24, 32, 48, 64, 128, 192, 256, 512]) {
    const publicTarget = path.join(publicIconsDir, `app-icon-${size}.png`);
    const resourceTarget = path.join(resourcesIconDir, `app-icon-${size}.png`);
    await renderIcon(iconSource, publicTarget, size);
    await renderIcon(iconSource, resourceTarget, size);
    if ([16, 32, 48, 64, 128, 256].includes(size)) iconPngs.push(resourceTarget);
  }
  const ico = await pngToIco(iconPngs);
  writeFileSync(path.join(resourcesIconDir, 'app-icon.ico'), ico);
  copyFileSync(path.join(resourcesIconDir, 'app-icon.ico'), path.join(publicIconsDir, 'app-icon.ico'));

  const soundManifest = {};
  for (const [key, filename] of Object.entries(sounds)) {
    const source = path.join(soundDir, filename);
    requireFile(source);
    const publicName = `${normalizedAndroidName(key)}.mp3`;
    copyFileSync(source, path.join(publicSoundsDir, publicName));
    copyFileSync(source, path.join(resourcesSoundDir, publicName));
    soundManifest[key] = `assets/sounds/${publicName}`;
  }

  const androidDir = path.join(appDir, 'android', 'app', 'src', 'main', 'res');
  if (existsSync(androidDir)) {
    const androidIcons = [
      ['mipmap-mdpi', 48],
      ['mipmap-hdpi', 72],
      ['mipmap-xhdpi', 96],
      ['mipmap-xxhdpi', 144],
      ['mipmap-xxxhdpi', 192],
    ];
    for (const [folder, size] of androidIcons) {
      const targetDir = path.join(androidDir, folder);
      ensureDir(targetDir);
      await renderIcon(iconSource, path.join(targetDir, 'ic_launcher.png'), size);
      await renderIcon(iconSource, path.join(targetDir, 'ic_launcher_round.png'), size);
    }
    const drawableDir = path.join(androidDir, 'drawable');
    const rawDir = path.join(androidDir, 'raw');
    ensureDir(drawableDir);
    ensureDir(rawDir);
    copyFileSync(path.join(logoDir, logos.dark), path.join(drawableDir, 'taskmaster_logo.png'));
    for (const [key, filename] of Object.entries(sounds)) {
      copyFileSync(path.join(soundDir, filename), path.join(rawDir, `${normalizedAndroidName(key)}.mp3`));
    }
  }

  const manifest = {
    generatedAt: new Date().toISOString(),
    source: 'media',
    logos: logoManifest,
    icons: {
      ico: 'assets/icons/app-icon.ico',
      png512: 'assets/icons/app-icon-512.png',
    },
    sounds: soundManifest,
    sourceFiles: {
      logos: Object.values(logos),
      sounds: Object.values(sounds),
    },
  };

  writeFileSync(path.join(publicAssetsDir, 'media-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  writeFileSync(path.join(resourcesDir, 'media-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log('TaskMaster Pro media assets synchronized.');
  console.log(`Logos: ${readdirSync(publicBrandingDir).length}, sounds: ${readdirSync(publicSoundsDir).length}`);
}

sync().catch((error) => {
  console.error(error);
  process.exit(1);
});
