#!/usr/bin/env node
// Regenerates Tests/EmperorCoreTests/Resources/parity/radar/limitation-radar.json from the
// platform's own Limitation Landmine Radar.
//
//   node scripts/generate-limitation-radar-fixtures.mjs <path-to-emperor-ai> [--check]
//
// The statutory profile table, the audit itself and the route's error envelopes come from
// `src/features/limitation-radar/{audit,route}.js`; the date wording is lifted by declaration from
// `src/pages/LimitationRadarPage.jsx`. Nothing is retyped: the app's profile strings, its wording
// and its decoding of every answer are held to what this file captures.
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL, fileURLToPath } from 'node:url'

const platform = process.argv[2]
const checkOnly = process.argv.includes('--check')
const dir = platform && path.join(platform, 'src/features/limitation-radar')
const pageFile = platform && path.join(platform, 'src/pages/LimitationRadarPage.jsx')
if (!dir || !fs.existsSync(path.join(dir, 'audit.js')) || !fs.existsSync(pageFile)) {
  console.error('usage: generate-limitation-radar-fixtures.mjs <path-to-emperor-ai> [--check]')
  process.exit(2)
}
const audit = await import(pathToFileURL(path.join(dir, 'audit.js')).href)
const route = await import(pathToFileURL(path.join(dir, 'route.js')).href)
const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)),
  '../Tests/EmperorCoreTests/Resources/parity/radar/limitation-radar.json')

// The page's own `days` and `longDate`, lifted by declaration so the fixture cannot drift from them.
const page = fs.readFileSync(pageFile, 'utf8')
const lift = (name) => {
  // A declaration runs to the first line that does not continue it: single line, or the
  // `=>` line followed by indented continuation lines.
  const m = page.match(new RegExp(`^const ${name} = [^\\n]*\\n(?:[ \\t]+[^\\n]*\\n)*`, 'm'))
  if (!m) throw new Error(`could not find "const ${name}" in LimitationRadarPage.jsx`)
  return m[0]
}
const { days, longDate } = new Function(`${lift('days')}\n${lift('longDate')}\nreturn { days, longDate }`)()

const inputs = [
  ['barred-17-days', { cause_of_action: '2023-01-15', intended_filing: '2026-02-01' }],
  ['on-the-last-day', { cause_of_action: '2023-01-15', intended_filing: '2026-01-15' }],
  ['one-day-late', { cause_of_action: '2023-01-15', intended_filing: '2026-01-16' }],
  ['one-day-remaining', { cause_of_action: '2023-01-15', intended_filing: '2026-01-14' }],
  ['barred-residuary-17-days', { profile: 'residuary', cause_of_action: '2023-01-15', intended_filing: '2026-02-01' }],
  ['safe-with-spare-days', { cause_of_action: '2023-01-15', intended_filing: '2024-06-01' }],
  ['mediation-reliant-amber', { cause_of_action: '2023-01-15', mediation_start: '2025-12-01', mediation_end: '2026-01-30', intended_filing: '2026-02-20' }],
  ['mediation-capped-five-months', { cause_of_action: '2024-01-01', mediation_start: '2025-01-01', mediation_end: '2025-12-31', intended_filing: '2027-03-01' }],
  ['mediation-end-assumed', { cause_of_action: '2023-01-15', mediation_start: '2025-12-01', intended_filing: '2026-02-20' }],
  ['mediation-began-after-expiry', { cause_of_action: '2023-01-15', mediation_start: '2026-01-20', mediation_end: '2026-02-10', intended_filing: '2026-02-15' }],
  ['mediation-still-barred', { cause_of_action: '2010-01-01', mediation_start: '2010-01-02', intended_filing: '2026-01-01' }],
  ['mediation-not-needed', { cause_of_action: '2023-01-15', mediation_start: '2025-06-01', mediation_end: '2025-07-01', intended_filing: '2025-12-20' }],
  ['month-end-clamp', { cause_of_action: '2023-10-01', mediation_start: '2025-09-30', intended_filing: '2026-06-01' }],
  ['leap-day-accrual', { cause_of_action: '2024-02-29', intended_filing: '2027-03-01' }],
  ...Object.keys(audit.PROFILES).map((key) =>
    [`profile-${key}`, { profile: key, cause_of_action: '2015-06-10', intended_filing: '2026-01-01' }]),
  ['legacy-key-mortgage', { profile: 'mortgage', cause_of_action: '2015-06-10', intended_filing: '2026-01-01' }],
]
const audits = inputs.map(([id, input]) => {
  const output = audit.auditLimitation(input)
  delete output.computed_at
  return { id, input, output }
})

// Route answers, captured through the route's own handler with a fake request and response.
const call = async (body) => {
  const handler = route.createLimitationRadarRoute()
  let status = 0
  let text = ''
  const res = {
    writableEnded: false,
    writeHead(s) { status = s },
    end(t) { text = t; this.writableEnded = true },
  }
  const buffer = Buffer.from(typeof body === 'string' ? body : JSON.stringify(body), 'utf8')
  const origError = console.error
  console.error = () => {}
  try { await handler.handle({ method: 'POST' }, res, buffer) } finally { console.error = origError }
  const response = JSON.parse(text)
  if (response.computed_at) delete response.computed_at
  return { status, response }
}
const routeCases = [
  ['missing-cause', { intended_filing: '2026-01-01' }],
  ['missing-filing', { cause_of_action: '2023-01-01' }],
  ['unknown-profile', { profile: 'no_such_suit', cause_of_action: '2023-01-01', intended_filing: '2024-01-01' }],
  ['filing-before-cause', { cause_of_action: '2024-01-01', intended_filing: '2023-01-01' }],
  ['mediation-end-before-start', { cause_of_action: '2023-01-01', intended_filing: '2024-01-01', mediation_start: '2023-06-01', mediation_end: '2023-05-01' }],
  ['invalid-json', '{not json'],
  ['non-string-date', { cause_of_action: 20230101, intended_filing: '2024-01-01' }],
]
const routes = []
for (const [id, body] of routeCases) routes.push({ id, body, ...(await call(body)) })

const dates = [
  '2026-01-15', '2026-02-28', '2023-02-28', '2027-02-28', '2025-06-01', '2000-12-31',
  '2024-02-29', '2026-03-16', '2030-09-01', '2010-01-02',
].map((iso) => ({ iso, long: longDate(iso) }))
const dayCounts = [-1, 0, 1, 2, 17, 151, 1079].map((n) => ({ n, text: days(n) }))

const fixture = {
  profiles: Object.values(audit.PROFILES),
  defaultProfile: audit.DEFAULT_PROFILE,
  legacyKeys: audit.LEGACY_PROFILE_KEYS,
  audits, routes, dates, dayCounts,
}
const text = JSON.stringify(fixture, null, 1) + '\n'
const before = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null
if (before === text) { console.log(`${audits.length} audits, ${routes.length} routes, unchanged`); process.exit(0) }
if (checkOnly) { console.log('limitation-radar.json differs from the platform'); process.exit(1) }
fs.mkdirSync(path.dirname(out), { recursive: true })
fs.writeFileSync(out, text)
console.log(`${audits.length} audits, ${routes.length} routes written`)
