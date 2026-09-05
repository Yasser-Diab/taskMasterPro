import fs from 'node:fs/promises'

const sourcePath = new URL('../lib/core/localization/app_localizations.dart', import.meta.url)
const dryRun = process.argv.includes('--dry-run')

function mapSlice(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker)
  const end = source.indexOf(endMarker, start)
  if (start < 0 || end < 0) throw new Error(`Unable to find ${startMarker}`)
  return source.slice(start, end)
}

function entriesFrom(source) {
  const entries = new Map()
  // Existing hand-written maps use single-quoted keys, while the generated
  // catalogue deliberately uses JSON-style double quotes so apostrophes stay
  // unambiguous. Accept both forms; otherwise a subsequent generation would
  // mistake every already-reviewed translation for a missing entry.
  const expression = /^\s*(?:'((?:\\.|[^'])+)'|"((?:\\.|[^"])*)"):\s*(?:\r?\n\s*)?(?:'((?:\\.|[^'])*)'|"((?:\\.|[^"])*)"),\s*$/gm
  for (const match of source.matchAll(expression)) {
    entries.set(
      (match[1] ?? match[2]).replaceAll("\\'", "'"),
      (match[3] ?? match[4]).replaceAll("\\'", "'"),
    )
  }
  return entries
}

function protectTemplate(value) {
  const tokens = []
  const protectedValue = value
    .replace(/\{[^{}]+\}/g, (match) => {
      const token = `__DVPH${tokens.length}__`
      tokens.push([token, match])
      return token
    })
    .replace(/\$[A-Za-z_][A-Za-z0-9_]*/g, (match) => {
      const token = `__DVPH${tokens.length}__`
      tokens.push([token, match])
      return token
    })
  return { protectedValue, tokens }
}

function restoreTemplate(value, tokens) {
  return tokens.reduce((result, [token, original]) => result.replaceAll(token, original), value)
}

async function translateBatch(batch) {
  const joined = batch
    .map(({ id, value }) => `<span data-dv="${id}"></span>${protectTemplate(value).protectedValue}`)
    .join('')
  const params = new URLSearchParams({ client: 'gtx', sl: 'en', tl: 'pl', dt: 't', q: joined })
  const response = await fetch(`https://translate.googleapis.com/translate_a/single?${params}`)
  if (!response.ok) throw new Error(`Translation request failed: ${response.status}`)
  const payload = await response.json()
  const translated = payload?.[0]?.map((part) => part[0]).join('')
  if (typeof translated !== 'string') throw new Error('Translation service returned no text')
  const chunks = new Map()
  const marker = /<span data-dv="(\d+)"><\/span>/g
  let match
  let previousId
  let previousEnd = 0
  while ((match = marker.exec(translated)) !== null) {
    if (previousId !== undefined) chunks.set(previousId, translated.slice(previousEnd, match.index))
    previousId = Number(match[1])
    previousEnd = marker.lastIndex
  }
  if (previousId !== undefined) chunks.set(previousId, translated.slice(previousEnd))
  if (chunks.size !== batch.length) {
    const expected = new Set(batch.map(({ id }) => id))
    const missing = [...expected].filter((id) => !chunks.has(id))
    // Google occasionally strips HTML separators around browser-security copy.
    // Those strings are safe to translate one at a time because no result
    // delimiter needs to survive.
    for (const entry of batch.filter(({ id }) => missing.includes(id))) {
      const protectedValue = protectTemplate(entry.value).protectedValue
      const singleParams = new URLSearchParams({ client: 'gtx', sl: 'en', tl: 'pl', dt: 't', q: protectedValue })
      const singleResponse = await fetch(`https://translate.googleapis.com/translate_a/single?${singleParams}`)
      if (!singleResponse.ok) throw new Error(`Fallback translation failed: ${singleResponse.status}`)
      const singlePayload = await singleResponse.json()
      const value = singlePayload?.[0]?.map((part) => part[0]).join('')
      if (typeof value !== 'string') throw new Error(`Fallback translation returned no text for ${entry.key}`)
      chunks.set(entry.id, value)
    }
  }
  return new Map(batch.map(({ id, value }) => [id, restoreTemplate(chunks.get(id), protectTemplate(value).tokens)]))
}

function dartString(value) {
  return JSON.stringify(value).replaceAll('$', '\\$')
}

function render(entries) {
  const lines = ['  /// Complete reviewed Polish client catalogue.', '  static const _polishOverrides = <String, String>{']
  for (const [key, value] of entries) lines.push(`    ${dartString(key)}: ${dartString(value)},`)
  lines.push('  };', '')
  return lines.join('\n')
}

const source = await fs.readFile(sourcePath, 'utf8')
const englishBase = entriesFrom(mapSlice(source, "    'en': {", "    'ar': {"))
const englishV26 = entriesFrom(mapSlice(source, '  static const _v26En', '  static const _v26Ar'))
const manualPolish = entriesFrom(mapSlice(source, '  static const _polishOverrides', '  static const delegate'))
const english = new Map([...englishBase, ...englishV26])

if (dryRun) {
  const missingKeys = [...english.keys()].filter((key) => !manualPolish.has(key))
  console.log(JSON.stringify({ english: english.size, existingPolish: manualPolish.size, missing: missingKeys.length, missingKeys }, null, 2))
  process.exit(0)
}

const missing = [...english.entries()]
  .filter(([key]) => !manualPolish.has(key))
  .map(([key, value], id) => ({ id, key, value }))
const translated = new Map()
const batches = []
let batch = []
let length = 0
for (const entry of missing) {
  const nextLength = protectTemplate(entry.value).protectedValue.length + 16
  if (batch.length > 0 && length + nextLength > 3600) {
    batches.push(batch)
    batch = []
    length = 0
  }
  batch.push(entry)
  length += nextLength
}
if (batch.length > 0) batches.push(batch)

for (const [index, current] of batches.entries()) {
  console.log(`Translating ${index + 1}/${batches.length} (${current.length} strings)`)
  const output = await translateBatch(current)
  for (const entry of current) translated.set(entry.key, output.get(entry.id))
}

const polish = new Map([...english].map(([key, value]) => [key, manualPolish.get(key) ?? translated.get(key) ?? value]))
if (polish.size !== english.size) throw new Error('Polish coverage is incomplete')
const start = source.lastIndexOf('  static const _polishOverrides')
const end = source.indexOf('  static const delegate', start)
if (start < 0 || end < 0) throw new Error('Unable to replace Polish catalogue')
await fs.writeFile(sourcePath, `${source.slice(0, start)}${render(polish)}${source.slice(end)}`)
console.log(`Wrote ${polish.size} Polish translations.`)
