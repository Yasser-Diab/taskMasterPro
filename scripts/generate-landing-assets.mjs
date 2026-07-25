import { chromium } from 'playwright'
import sharp from 'sharp'
import { mkdir, readFile } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const scriptDirectory = dirname(fileURLToPath(import.meta.url))
const projectRoot = resolve(scriptDirectory, '..')
const landingRoot = join(projectRoot, 'landing-page')
const outputDirectory = join(landingRoot, 'assets', 'screenshots')

await mkdir(outputDirectory, { recursive: true })

const browser = await chromium.launch({
  headless: true,
  executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
})
const page = await browser.newPage({
  viewport: { width: 1520, height: 980 },
  deviceScaleFactor: 1,
})

await page.goto(pathToFileURL(join(scriptDirectory, 'landing-demo-screens.html')).href)
await page.waitForLoadState('load')

const shots = [
  ['dashboard', 'dashboard.webp'],
  ['roadmap', 'roadmap.webp'],
  ['active-task', 'active-task.webp'],
  ['reports', 'reports.webp'],
]

for (const [id, name] of shots) {
  const element = page.locator(`#${id}`)
  const png = await element.screenshot({ type: 'png' })
  await sharp(png).webp({ quality: 82, smartSubsample: true }).toFile(
    join(outputDirectory, name),
  )
}

const dashboard = await readFile(join(outputDirectory, 'dashboard.webp'))
for (const width of [640, 1024, 1600]) {
  await sharp(dashboard)
    .resize({ width, withoutEnlargement: false })
    .webp({ quality: 80, smartSubsample: true })
    .toFile(join(outputDirectory, `dashboard-${width}.webp`))
}

const sourceLogo = join(
  projectRoot,
  'media',
  'app-logo',
  'TaskMaster_Pro_Blue_Dark_Transparent.png',
)
const optimizedLogo = join(
  landingRoot,
  'assets',
  'images',
  'taskmaster-logo.webp',
)
await sharp(sourceLogo)
  .resize({ width: 620, withoutEnlargement: true })
  .webp({ quality: 88, alphaQuality: 95 })
  .toFile(optimizedLogo)

await browser.close()
