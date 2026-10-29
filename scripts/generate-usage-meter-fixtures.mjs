#!/usr/bin/env node
// Regenerates the usage-meter golden cases from the platform's own source.
//
//   node scripts/generate-usage-meter-fixtures.mjs <path-to-emperor-ai> [--check]
//
// The web's usage meter is `rowsFor` (src/components/billing/UsageMeter.jsx) over the helpers in
// src/lib/useEntitlements.js, fed by the allowances in lib/planLimits.js. Those two files import
// React, so they cannot be loaded whole: the helpers are lifted by declaration and evaluated
// here, and `planLimits.js` (pure) is imported as it stands. If the platform rewrites any of
// them, the matches below fail loudly instead of producing stale cases.
//
// Also emitted: the top bar's customer-facing plan-name filter (src/shell/Topbar.jsx), lifted
// as the expression it is.
//
// Writes Tests/EmperorCoreTests/Resources/parity/08-O/usage-meter.json. `--check` writes nothing
// and exits 1 if the committed file differs.

import { pathToFileURL, fileURLToPath } from 'node:url'
import fs from 'node:fs'
import path from 'node:path'

const platform = process.argv[2]
const checkOnly = process.argv.includes('--check')
if (!platform || !fs.existsSync(path.join(platform, 'lib/planLimits.js'))) {
  console.error('usage: generate-usage-meter-fixtures.mjs <path-to-emperor-ai> [--check]')
  process.exit(2)
}
const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)),
  '../Tests/EmperorCoreTests/Resources/parity/08-O/usage-meter.json')

const read = (rel) => fs.readFileSync(path.join(platform, rel), 'utf8')
const fail = (msg) => { console.error(msg); process.exit(1) }

// ── useEntitlements.js: everything from `isUnlimited` down is pure.
const hooks = read('src/lib/useEntitlements.js')
const start = hooks.indexOf('export const isUnlimited')
if (start < 0) fail('isUnlimited not found in src/lib/useEntitlements.js — the platform has changed shape')
const helperSource = hooks.slice(start).replace(/export /g, '')
// eslint-disable-next-line no-new-func
const H = new Function(`${helperSource}
return { isUnlimited, effectiveLimits, fmtBytes, usageTone, resetDateLabel, exhausted }`)()

// ── UsageMeter.jsx: `n` and `rowsFor`.
const meter = read('src/components/billing/UsageMeter.jsx')
const nDecl = meter.match(/const n = \(v\) => [^\n]+/)
const rowsDecl = meter.match(/function rowsFor\(ent\) \{[\s\S]*?\n\}\n/)
if (!nDecl || !rowsDecl) fail('n / rowsFor not found in UsageMeter.jsx — the platform has changed shape')
// eslint-disable-next-line no-new-func
const rowsFor = new Function('effectiveLimits', 'isUnlimited', 'fmtBytes',
  `${nDecl[0]}\n${rowsDecl[0]}\nreturn rowsFor`)(H.effectiveLimits, H.isUnlimited, H.fmtBytes)

// ── Topbar.jsx: the customer-facing filter.
const topbar = read('src/shell/Topbar.jsx')
const filterExpr = topbar.match(/const planLabel = (user\?\.planLabel && ![^\n]+)\n/)
if (!filterExpr) fail('planLabel filter not found in Topbar.jsx — the platform has changed shape')
// eslint-disable-next-line no-new-func
const topbarLabel = new Function('user', `return ${filterExpr[1]}`)

const PL = await import(pathToFileURL(path.join(platform, 'lib/planLimits.js')).href)

const GiB = 1024 ** 3
const rowOut = (r) => ({
  key: r.key, title: r.title, usedText: r.usedText, limitText: r.limitText,
  unlimited: H.isUnlimited(r.limit), tone: H.usageTone(r.used, r.limit),
})

// Entitlement bodies as `/billing/entitlements` builds them (sync-server.js): the tier's limits,
// the usage block, `metered`.
const body = (name, { limits, metered, usage }) => {
  const storageAllowanceBytes = PL.unlimited(limits.storageGb) ? PL.UNLIMITED : PL.storageBytesFor(limits.storageGb)
  const ent = {
    success: true, signedIn: true, metered, limits,
    usage: {
      period: '2026-10', resetsAt: '2026-10-31T18:30:00.000Z',
      matters: 2, storageAllowanceBytes, ...usage,
    },
  }
  return { name, body: ent, rows: rowsFor(ent).map(rowOut), exhausted: H.exhausted(ent),
    reset: H.resetDateLabel(ent.usage.resetsAt) }
}
const mid = { chatQueries: 812, deepThinkingQueries: 4, scannedPages: 120, documents: 44, storageUsedBytes: Math.round(2.4 * GiB) }
const bodies = [
  body('free metered', { limits: PL.limitsFor('free'), metered: true, usage: { ...mid, chatQueries: 24, documents: 500 } }),
  body('junior associate metered', { limits: PL.limitsFor('essential'), metered: true, usage: mid }),
  body('senior associate metered', { limits: PL.limitsFor('premium'), metered: true, usage: { ...mid, scannedPages: 48000, storageUsedBytes: Math.round(199.96 * GiB) } }),
  body('partner metered, storage unlimited', { limits: PL.limitsFor('ultimate'), metered: true, usage: mid }),
  body('unmetered staff on junior associate', { limits: PL.limitsFor('essential'), metered: false, usage: mid }),
  body('earlier plan, unmetered', { limits: PL.LEGACY_LIMITS, metered: false, usage: { ...mid, storageUsedBytes: 850 * 1024 ** 2 } }),
  body('junior associate spent', { limits: PL.limitsFor('essential'), metered: true, usage: { ...mid, chatQueries: 3000, deepThinkingQueries: 300, storageUsedBytes: 50 * GiB } }),
]

const fmtInputs = [0, 1024 ** 2 - 1, 850 * 1024 ** 2, GiB, Math.round(2.4 * GiB), Math.round(99.95 * GiB),
  150 * GiB, 1500 * GiB, -1]
const fmtCases = fmtInputs.map(v => ({ bytes: v, text: H.fmtBytes(v) }))

const toneCases = []
for (const limit of [-1, null, 0, 100]) {
  for (const used of [0, 50, 79, 80, 99, 100, 101]) {
    toneCases.push({ used, limit, tone: H.usageTone(used, limit) })
  }
}

const topbarCases = ['Partner', 'Ultra', 'Lite', 'Premium', 'None', '', null, 'Earlier plan', 'Junior Associate']
  .map(label => ({ label, shown: topbarLabel({ planLabel: label }) || null }))

const json = JSON.stringify({
  note: 'Generated by scripts/generate-usage-meter-fixtures.mjs from the platform; do not edit.',
  fmtBytes: fmtCases, usageTone: toneCases, bodies, topbar: topbarCases,
}, null, 2) + '\n'

if (checkOnly) {
  const current = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : ''
  if (current !== json) { console.error('usage-meter.json is out of date with the platform'); process.exit(1) }
  console.log('usage-meter.json matches the platform')
} else {
  fs.mkdirSync(path.dirname(out), { recursive: true })
  fs.writeFileSync(out, json)
  console.log(`wrote ${bodies.length} bodies, ${fmtCases.length} byte cases to ${path.relative(process.cwd(), out)}`)
}
