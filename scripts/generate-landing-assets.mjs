import { copyFile, mkdir, readFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const require = createRequire(import.meta.url)
const { chromium } = require('playwright')
const sharp = require('sharp')

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

// Keep the public Health preview tied to a captured, installed Android build.
// The committed output remains available to the landing page; the QA capture
// is regenerated whenever the release is verified on the connected phone.
await sharp(
  join(projectRoot, 'build', 'qa-captures', 'dayvector-health-weekly-workouts.png'),
)
  .resize({ width: 852 })
  .png({ compressionLevel: 9, adaptiveFiltering: true })
  .toFile(
    join(landingRoot, 'assets', 'images', 'health-dashboard-phone-clean.png'),
  )

const approvedBrand = join(projectRoot, 'DayVectorNewBranding')
const brandOutput = join(landingRoot, 'assets', 'brand')
await mkdir(brandOutput, { recursive: true })
await copyFile(
  join(approvedBrand, '01_Master_Artwork', 'DayVector_Symbol_Approved_Exact.svg'),
  join(brandOutput, 'dayvector-symbol.svg'),
)
await copyFile(
  join(approvedBrand, '01_Master_Artwork', 'DayVector_Lockup_Horizontal.svg'),
  join(brandOutput, 'dayvector-horizontal.svg'),
)
await copyFile(
  join(approvedBrand, '01_Master_Artwork', 'DayVector_Lockup_Dark.svg'),
  join(brandOutput, 'dayvector-horizontal-dark.svg'),
)

await browser.close()
