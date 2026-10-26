#!/usr/bin/env node
// Regenerates the matter-rules golden fixture from the platform's own source.
//
//   node scripts/generate-matter-fixtures.mjs <path-to-emperor-ai> [--check]
//
// A matter's money, dates, chronology, names and receipt are decided by the web's own modules:
// `src/components/projects/money/{inr,ledger,dates,receipt}.js`, `lib/projects/rules.js` (the
// server's rules), `src/lib/courtNames.js`, `src/lib/projectRecord.js`, `src/lib/projectColors.js`,
// `src/lib/projectsApi.js`, `src/components/projects/{projectMeta,trackCase}.js`,
// `src/components/matters/trackedCases.js` and `src/components/lookup/lookupModel.js`. They are
// imported for real, under Node, and every case below is run through them; the app's port
// (`CourtNames`, `MatterRules`, `INR`, `Ledger`, `MatterDates`, `MatterRecord`, `MatterMeta`,
// `MatterReceipt`, `MatterVocabulary`, `MatterBanner`) is held to the answers.
//
// Values that live only inside a .jsx file (the banner presets, the forum/status/priority lists,
// the status dots) or are private to a module (`extIdOf`, `canon`, the field limits) are cut out
// of the source by name and evaluated, so a renamed constant fails this script loudly.
//
// Determinism: every call that would read the clock is given `today` ('2026-10-12') or a fixed
// instant, and the process runs in UTC so a zoneless timestamp means the same instant everywhere.
// `inr()` and `rupeesFigure()` need a Node with full ICU (the default builds); that is asserted.
//
// Output: `Tests/EmperorCoreTests/MatterGolden.swift`, a Swift source file rather than a resource,
// so it needs no change to Package.swift or project.yml.
//
// `--check` writes nothing and exits 1 if the fixture differs.

process.env.TZ = 'UTC'

import { registerHooks } from 'node:module'
import { pathToFileURL, fileURLToPath } from 'node:url'
import fs from 'node:fs'
import path from 'node:path'

const platform = process.argv[2]
const checkOnly = process.argv.includes('--check')
if (!platform || !fs.existsSync(path.join(platform, 'lib/projects/rules.js'))) {
  console.error('usage: generate-matter-fixtures.mjs <path-to-emperor-ai> [--check]')
  process.exit(2)
}
const root = path.resolve(platform)
const src = path.join(root, 'src')
const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../Tests/EmperorCoreTests/MatterGolden.swift')

if ((1234567).toLocaleString('en-IN') !== '12,34,567') {
  console.error('this Node has no en-IN locale data (small-icu); use a full-ICU build')
  process.exit(1)
}

// `@/` is the web's alias for src/. lucide-react resolves each icon to its own name, and the
// zustand store is a stand-in: trackCase.js imports it but findTrackedCase never touches it.
const lucideStub = new Proxy({}, { get: (_, k) => k })
registerHooks({
  resolve(specifier, context, next) {
    if (specifier === 'lucide-react') return { url: 'emperor-stub:lucide', shortCircuit: true }
    let target = null
    if (specifier.startsWith('@/')) target = path.join(src, specifier.slice(2))
    else if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      target = path.resolve(path.dirname(fileURLToPath(context.parentURL)), specifier)
    }
    if (target === path.join(src, 'lib/store')) return { url: 'emperor-stub:store', shortCircuit: true }
    if (target) {
      for (const candidate of [target, `${target}.js`, `${target}.jsx`, path.join(target, 'index.js')]) {
        if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
          return { url: pathToFileURL(candidate).href, shortCircuit: true }
        }
      }
    }
    return next(specifier, context)
  },
  load(url, context, next) {
    if (url === 'emperor-stub:lucide') {
      const names = new Set()
      for (const file of walk(src)) {
        const text = fs.readFileSync(file, 'utf8')
        for (const m of text.matchAll(/import\s*\{([^}]*)\}\s*from\s*['"]lucide-react['"]/g)) {
          for (const part of m[1].split(',')) {
            const name = part.trim().split(/\s+as\s+/)[0].trim()
            if (/^[A-Za-z_$][\w$]*$/.test(name)) names.add(name)
          }
        }
      }
      return { format: 'module', source: [...names].map(n => `export const ${n} = '${n}';`).join('\n'), shortCircuit: true }
    }
    if (url === 'emperor-stub:store') {
      return { format: 'module', source: 'export const useStore = { getState: () => ({}) };', shortCircuit: true }
    }
    if (url.startsWith('file:') && url.startsWith(pathToFileURL(root).href) && /\.(js|jsx|mjs)$/.test(url)) {
      return { format: 'module', source: fs.readFileSync(fileURLToPath(url), 'utf8'), shortCircuit: true }
    }
    return next(url, context)
  },
})
void lucideStub

const imp = (rel) => import(pathToFileURL(path.join(root, rel)).href)
const inr = await imp('src/components/projects/money/inr.js')
const ledger = await imp('src/components/projects/money/ledger.js')
const dates = await imp('src/components/projects/money/dates.js')
const receipt = await imp('src/components/projects/money/receipt.js')
const rules = await imp('lib/projects/rules.js')
const courtNames = await imp('src/lib/courtNames.js')
const record = await imp('src/lib/projectRecord.js')
const colors = await imp('src/lib/projectColors.js')
const api = await imp('src/lib/projectsApi.js')
const meta = await imp('src/components/projects/projectMeta.js')
const tracked = await imp('src/components/matters/trackedCases.js')
const trackCase = await imp('src/components/projects/trackCase.js')
const lookup = await imp('src/components/lookup/lookupModel.js')
const courts = await imp('src/lib/courts.js')

// \u2500\u2500 Cut from source \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8')
const cut = (text, re, what) => {
  const m = text.match(re)
  if (!m) { console.error(`${what} not found — the cut is stale`); process.exit(1) }
  return m[1]
}
const evalJs = (code) => new Function(`return (${code})`)()
const bannerSource = read('src/components/projects/ProjectBanner.jsx')
const PRESETS = evalJs(cut(bannerSource, /const\s+PRESETS\s*=\s*(\{[\s\S]*?\n\})/, 'PRESETS'))
const mixMatch = bannerSource.match(/`linear-gradient\(135deg, \$\{mix\(from, (\d+)\)\} 0%, \$\{mix\(to, (\d+)\)\} 100%\)`/)
if (!mixMatch) { console.error('banner mix percentages not found'); process.exit(1) }
const plateMatch = bannerSource.match(/const PLATE = \{\s*background: 'rgba\((\d+), (\d+), (\d+), (\.\d+)\)'/)
if (!plateMatch) { console.error('banner PLATE not found'); process.exit(1) }
const sharedSource = read('src/components/projects/shared.jsx')
const listOf = (name) => evalJs(cut(sharedSource, new RegExp(`export const ${name}\\s*=\\s*(\\[[\\s\\S]*?\\n\\])`), name)
  .replace(/,\s*icon:\s*\w+/g, ''))
const FORUMS = listOf('FORUMS')
const STATUSES = listOf('STATUSES')
const PRIORITIES = listOf('PRIORITIES')
const workspaceSource = read('src/pages/ProjectWorkspace.jsx')
const STATUS_DOT = evalJs(cut(workspaceSource, /const\s+STATUS_DOT\s*=\s*(\{[^}]*\})/, 'STATUS_DOT'))
const trackSource = read('src/components/projects/trackCase.js')
const extIdOf = evalJs(cut(trackSource, /const\s+extIdOf\s*=\s*(\(b\)\s*=>[^\n]*)/, 'extIdOf'))
const canon = evalJs(cut(trackSource, /const\s+canon\s*=\s*(\(s\)\s*=>[^\n]*)/, 'canon'))
const rulesSource = read('lib/projects/rules.js')
const fieldBlock = cut(rulesSource, /const PROJECT_FIELDS = \{([\s\S]*?)\n\};/, 'PROJECT_FIELDS')
const limits = {}
for (const m of fieldBlock.matchAll(/(\w+): \['\w+', \(v\) => (?:opt|req)Text\(v, '[^']*', (\d+)\)\]/g)) limits[m[1]] = Number(m[2])
const ourSideMax = cut(rulesSource, /function ourSideOf[\s\S]*?optText\(value, 'ourSide', (\d+)\)/, 'ourSideOf max')
limits.ourSide = Number(ourSideMax)
const bodyOf = (name) => cut(rulesSource, new RegExp(`export function ${name}\\(([\\s\\S]*?)\\n\\}`), name)
for (const [prefix, fn] of [['update', 'updateColumns'], ['task', 'taskColumns'], ['ledger', 'ledgerColumns'], ['person', 'personColumns']]) {
  for (const m of bodyOf(fn).matchAll(/(?:opt|req)Text\(input\.(\w+), '[^']*', (\d+)\)/g)) limits[`${prefix}.${m[1]}`] = Number(m[2])
}
limits['ledger.receiptFile'] = Number(cut(rulesSource, /optText\(value, 'receiptFile', (\d+)\)/, 'receiptFile max'))
limits['person.email'] = Number(cut(rulesSource, /optText\(value, 'email', (\d+)\)/, 'email max'))
limits['person.phone'] = Number(cut(rulesSource, /optText\(value, 'phone', (\d+)\)/, 'phone max'))

// \u2500\u2500 Cases \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
const cases = []
const add = (fn, input, expected) => cases.push({ fn, input, expected: expected === undefined ? null : expected })
// A number JSON cannot carry (NaN, \u00b1Infinity) travels as {"special": "..."}.
const num = (n) => (Number.isFinite(n) ? n : { special: String(n) })
const attempt = (f) => { try { return { ok: f() ?? null } } catch (e) { return { error: e.message } } }
const TODAY = '2026-10-12'

// Vocabularies
const pairs = (list) => list.map(([k, l]) => [k, l])
const vocab = {
  practiceAreas: pairs(api.PRACTICE_AREAS),
  ourSides: pairs(api.OUR_SIDES),
  banners: api.BANNERS.map(k => [k, k[0].toUpperCase() + k.slice(1)]),
  taskKinds: pairs(api.TASK_KINDS),
  expenseCategories: pairs(api.EXPENSE_CATEGORIES),
  paymentModes: pairs(api.PAYMENT_MODES),
  peopleRoles: pairs(api.PEOPLE_ROLES),
  sections: pairs(api.SECTIONS),
  ledgerKinds: pairs(ledger.LEDGER_KINDS),
  chronoKinds: record.CHRONO_KINDS.map(k => [k.value, k.label]),
  sources: Object.entries(record.SOURCE_LABEL),
  projectColors: colors.PROJECT_COLORS.map(c => [c.key, c.label]),
  forums: FORUMS.map(f => [f.value, f.label]),
  statuses: STATUSES.map(s => [s.value, s.label]),
  priorities: PRIORITIES.map(p => [p.value, p.label]),
  taskGroups: pairs(dates.TASK_GROUPS),
}
for (const [name, list] of Object.entries(vocab)) add('vocab', { name }, list)
const serverVocab = {
  courtStatuses: rules.COURT_STATUSES, practiceAreas: rules.PRACTICE_AREAS, ourSides: rules.OUR_SIDES,
  banners: rules.BANNER_PRESETS, projectStatuses: rules.PROJECT_STATUSES, priorities: rules.PRIORITIES,
  updateKinds: rules.UPDATE_KINDS, updateSources: rules.UPDATE_SOURCES, taskKinds: rules.TASK_KINDS,
  taskStatuses: rules.TASK_STATUSES, ledgerKinds: rules.LEDGER_KINDS, paymentModes: rules.PAYMENT_MODES,
  expenseCategories: rules.EXPENSE_CATEGORIES, peopleRoles: rules.PEOPLE_ROLES, criticalKinds: dates.CRITICAL_KINDS,
}
for (const [name, list] of Object.entries(serverVocab)) add('serverVocab', { name }, list)
add('constants', {}, {
  clientMaxRupees: inr.MAX_RUPEES, serverMaxRupees: rules.MAX_RUPEES, soonDays: dates.SOON_DAYS,
  bannerMaxBytes: rules.BANNER_MAX_BYTES, bannerExts: rules.BANNER_EXTS, bannerMimeByExt: rules.BANNER_MIME_BY_EXT,
  caseRefreshGapMs: rules.CASE_REFRESH_GAP_MS, trackedPrefix: tracked.TRACKED_PREFIX, fieldLimits: limits,
  referenceField: ledger.REFERENCE_FIELD, expenseReference: ledger.EXPENSE_REFERENCE,
  categoryLabels: courts.CATEGORY_LABEL,
})
add('banner', {}, {
  presets: PRESETS, fromPercent: Number(mixMatch[1]), toPercent: Number(mixMatch[2]),
  plate: plateMatch.slice(1, 5).map(Number), statusDot: STATUS_DOT,
})

// Collation (String.prototype.localeCompare), which every sort in these modules uses.
const collate = ['', 'a', 'A', 'b', 'B', 'ab', 'Ab', 'aB', 'a-b', 'a b', 'a_b', 'a.b', 'a1', 'a10', 'a2', '1', '10', '9',
  'Receipts', 'receipts', 'Orders', 'orders', '_x', 'x_', 'Brief.docx', 'brief.docx', 'Brief-2.docx', 'Brief 2.docx',
  'Court fee', 'Clerkage', 'Other', 'Typing & copies', 'Notary / oath', '2026-10-12', '2026-10-12 09:00:00',
  '2026-10-12T09:00:00.000Z', '2026-10-1', '(a)', '[a]', '#1', '$1', '~a', '\u00e9', 'e', 'f', '\u00c9', 'z', 'Z', 'zz',
  '\u00dcn\u00efcode', 'Unicode', 'r\u00e9sum\u00e9', 'resume', 'Resume']
for (const a of collate) for (const b of collate) add('localeCompare', { a, b }, Math.sign(a.localeCompare(b)))

// Court names
const tidyCases = [
  ['TATA CAPITAL LTD vs. MANOJ BHADANA', true],
  ['M/S NEW DELHI TYRE HOUSE vs. STATE NCT OF DELHI AND ANR.', true],
  ['Sharma vs. Delhi Development Authority', true],
  ['RAM LAL v/s SHYAM LAL', true], ['RAM LAL VERSUS SHYAM LAL', true], ['STATE V. K. V. RAO', true],
  ['K. V. RAO V. STATE', true], ['K. V. RAO vs. STATE OF U.P.', true], ['RAM S/O V. K. SHARMA', true],
  ['S.K.SHARMA vs. UOI', true], ['RAM KUMAR (PROPRIETOR) v/s SHYAM TRADERS PVT. LTD.', true],
  ['GOVT. OF NCT, DELHI vs. (UOI)', true], ['DR. RK SHARMA vs. XYZ CO.', true], ['AL-AMEEN TRUST vs. STATE', true],
  ["SHARMA'S BAKERY vs. MCD", true], [`${'A'.repeat(150)} vs. ${'B'.repeat(150)}`, true],
  ['K. V. RAO', false], ['STATE THROUGH PS LAJPAT NAGAR', false], ['Asha Mehta', false], ['A'.repeat(250), false],
  [null, false], [null, true], ['', true], ['   ', true],
  ['STATE V RAM', true], ['STATE V RAM', false], ['V. RAM', true], ['RAM V.', true], ['RAM V. SHYAM VS. X', true],
  ['UNION OF INDIA THROUGH SECRETARY, MINISTRY OF HOME AFFAIRS AND ORS vs. ABC', true],
  ['M/S. ABC ENTERPRISES ANR', false], ['C/O RAM V. SHYAM', true], ['D/O. V. SITA', true],
  ['STATE OF J&K vs. ICICI BANK LTD.', true], ['XYZ PVT LTD WITH ABC LLP', false], ['IN RE: ABC', false],
  ['THE STATE vs. THE ACCUSED', true], ['ABC', false], ['abc vs. def', true], ['ABCD', false],
  ['RAJ KUMAR @ RAJU vs. STATE (GNCTD)', true], ['ITO WARD 12(3) vs. ABC 2ND FLOOR', true],
  ['\u0930\u093e\u092e \u0932\u093e\u0932 \u092c\u0928\u093e\u092e \u0936\u094d\u092f\u093e\u092e', true],
  ['\u0930\u093e\u092e '.repeat(60) + 'vs. STATE', true],
  ['RAM\u00a0LAL\tvs.\nSHYAM  LAL', true], ['O\u2019BRIEN vs. STATE', true], ["O'BRIEN vs. STATE", true],
  ['MC-DONALD vs. A-B-C', true], ['II ADDL. SESSIONS JUDGE', false], ['M/S vs. M/S', true],
]
for (const [raw, title] of tidyCases) add('tidyCourtName', { raw, title }, courtNames.tidyCourtName(raw, { title }))

// inr.js
for (const n of [0, 1, 0.29, 0.1 + 0.2, 1.005, 12.5, -12.5, 1234567.89, 1e12, 25000, NaN, Infinity, -Infinity, 0.075, 0.125, 2.675, 1e-7]) {
  add('toPaise.number', { amount: num(n) }, inr.toPaise(n))
}
for (const s of ['', ' ', '1,25,000', '25000.50', '0.075', '-12.5', '12a', '.5', '5.', '.', '-', '1 000', '0.005', '0.004',
  '0.0049', '12.345', '00012', 'abc', '1,2,3', '1e5', '+5', '9.995', '99999999999999']) {
  add('toPaise.text', { amount: s }, inr.toPaise(s))
}
const wordAmounts = [0, 1, 10, 11, 19, 20, 21, 99, 100, 101, 110, 999, 1000, 1001, 10000, 25000, 99999, 100000, 125000,
  200000, 1234567, 9999999, 10000000, 10000001, 10100000, 12345678, 1000000000, 12000000000, 123456789012, 0.5, 0.05,
  1.05, 1234.56, 100000.99, 0.29, 0.1 + 0.2, 1234567.89, -1, NaN, Infinity, inr.MAX_RUPEES, inr.MAX_RUPEES + 1,
  999999999999.99, 70, 15.15, 1e11]
for (const n of wordAmounts) add('amountInWordsINR.number', { amount: num(n) }, inr.amountInWordsINR(n))
for (const s of ['1,25,000', '25000.50', '0.075', '', 'abc', '12a', '0.004', '-5']) {
  add('amountInWordsINR.text', { amount: s }, inr.amountInWordsINR(s))
}
const parseInputs = ['25000', '25,000', '1,25,000.50', '1,250,000', ' 500 ', '₹ 500', '₹500', 'Rs. 500', 'rs 500', 'Rs.500',
  'INR 500', 'inr500', '25000/-', '₹25,000/-', '0.5', '.75', '10.', '0.01', '1000000000000', '1000000000000.01',
  // refusals
  '', '   ', '0', '0.00', '-5', 'abc', '12a', '1.234', '1..2', '.', '₹', '1e5', String(inr.MAX_RUPEES * 10), 'Rs.',
  '/-', '₹ ₹ 5', '5/-/-', '12,34.5.6', 'INR', '+5', '$5', '5 rupees', '0.001', '00.00']
for (const s of parseInputs) add('parseRupees', { text: s }, inr.parseRupees(s))
for (const n of [25000, 125000, 12345678.5, 0.05, NaN, 0, 1e7, 1e12, 100.1, -5, 1234567.891, 99.999]) {
  add('rupeesFigure.number', { amount: num(n) }, inr.rupeesFigure(n))
}
for (const d of ['2026-10-12', '2026-04-01', '2026-03-31', '2099-12-31', '', null, '2026-10-12 10:00:00', '12-10-2026', '1999-04-01']) {
  add('financialYear', { day: d }, inr.financialYear(d))
}
const receiptEntries = [
  { id: 'pl_1760270000000_ab12cd', entry_date: '2026-10-12' },
  { id: 'pl_1760270000000_ab12cd', entry_date: '2026-02-01' },
  { id: 'x1', entry_date: '', created_at: '2026-05-02 10:00:00' },
  { id: '', entry_date: '2026-10-12' },
  { id: 'a-b_c' },
  { id: 'pl_17602_\u0928\u094d\u092f\u093e\u092f_zz', entry_date: '2027-01-05' },
  { id: null, entry_date: null, created_at: null },
  { id: 'ABCDEFGHIJ', created_at: '2026-03-31T20:00:00.000Z' },
]
for (const e of receiptEntries) add('receiptNumber', e, inr.receiptNumber(e))

// projectsApi.inr and ledger.rupees
for (const n of [0, 1, 25000, 125000.5, 125000.25, 0.5, -75001.5, 1.005, 1.995, 1.999, 1.001, 1e7, 123456789.12, 1e12,
  -0.001, 0.1 + 0.2, 99.995, 5e-324, 1234.5678, 1e21, 12345678901234567890]) {
  add('inr', { rupees: n }, api.inr(n))
  add('rupees', { rupees: n }, ledger.rupees(n))
}

// ledger.js
for (const e of [{ amount_paise: 2500050, amount: 1 }, { amount_paise: '2500050' }, { amount: 0.29 }, {}, { amount_paise: 12.5, amount: 3 },
  { amount_paise: '12a', amount: 7 }, { amount_paise: null, amount: 1.005 }, { amount_paise: 0, amount: 9 }, { amount_paise: -50 }]) {
  add('paiseOf', { entry: e }, ledger.paiseOf(e))
}
const ledgerEntries = [
  { id: 'f1', kind: 'fee', amount_paise: 15000000, entry_date: '2026-09-01', created_at: '2026-09-01 10:00:00' },
  { id: 'p1', kind: 'payment', amount_paise: 5000000, entry_date: '2026-09-05', created_at: '2026-09-05 10:00:00' },
  { id: 'p2', kind: 'payment', amount_paise: 2500050, entry_date: '2026-10-12', created_at: '2026-10-12 09:00:00' },
  { id: 'e1', kind: 'expense', category: 'court_fee', amount_paise: 125000, entry_date: '2026-09-02' },
  { id: 'e2', kind: 'expense', category: 'clerkage', amount_paise: 50000, entry_date: '2026-09-02' },
  { id: 'e3', kind: 'expense', category: 'court_fee', amount_paise: 25000, entry_date: '2026-10-01' },
  { id: 'e4', kind: 'expense', category: 'nonsense', amount_paise: 10000, entry_date: '' },
]
const ledgerSets = {
  selftest: ledgerEntries,
  empty: [],
  sameDay: [
    { id: 'a', kind: 'fee', amount: 100, entry_date: '2026-10-12', created_at: '2026-10-12 08:00:00' },
    { id: 'b', kind: 'fee', amount: 200.5, entry_date: '2026-10-12', created_at: '2026-10-12 11:00:00' },
    { id: 'c', kind: 'payment', amount: 300, entry_date: '2026-10-12T22:00:00Z', created_at: '' },
    { id: 'd', kind: 'payment', amount: 0.1, entry_date: '2026-02-30', created_at: '2026-01-01 00:00:00' },
    { id: 'e', kind: 'refund', amount: 50, entry_date: '2026-10-11' },
    { id: 'f', kind: 'expense', category: 'travel', amount: 0.2, entry_date: '2026-10-10' },
    { id: 'g', kind: 'expense', category: 'notary', amount: 0.2, entry_date: '2026-10-10' },
    { id: 'h', kind: 'expense', category: 'stamp_duty', amount: 0.2, entry_date: '2026-10-10' },
    { id: 'i', kind: 'expense', amount: 0.2, entry_date: '2026-10-10' },
  ],
  advance: [{ id: 'p', kind: 'payment', amount_paise: 100 }],
}
for (const [name, list] of Object.entries(ledgerSets)) {
  add('sortEntries', { name, entries: list }, ledger.sortEntries(list).map(e => e.id))
  add('ledger.ledgerTotals', { name, entries: list }, ledger.ledgerTotals(list))
  add('expenseCategories', { name, entries: list }, ledger.expenseCategories(list))
}
for (const m of ['upi', 'bank', 'cheque', 'cash', 'card', 'other', 'nonsense', null]) add('modeLabel', { mode: m }, ledger.modeLabel(m))
for (const c of ['court_fee', 'stamp_duty', 'other', 'nonsense', null]) add('categoryLabel', { category: c }, ledger.categoryLabel(c))
const listings = {
  selftest: {
    root: '_projects/p1',
    folders: [
      { name: 'Orders', path: '_projects/p1/Orders', type: 'folder', files: [
        { name: 'Order_2026-09-01.pdf', path: '_projects/p1/Orders/Order_2026-09-01.pdf', type: 'file' },
      ] },
      { name: 'Receipts', path: '_projects/p1/Receipts', type: 'folder', files: [
        { name: 'UPI_slip.pdf', path: '_projects/p1/Receipts/UPI_slip.pdf', type: 'file' },
        { name: '2026', path: '_projects/p1/Receipts/2026', type: 'folder', files: [
          { name: 'Challan.pdf', path: '_projects\\p1\\Receipts\\2026\\Challan.pdf', type: 'file' },
        ] },
      ] },
    ],
    files: [{ name: 'Brief.docx', path: '_projects/p1/Brief.docx', type: 'file' }],
  },
  mixedCase: {
    root: '_projects/p2/',
    folders: [
      { name: 'receipts', path: '_projects/p2/receipts', type: 'folder', files: [
        { name: 'b.pdf', path: '_projects/p2/receipts/b.pdf', type: 'file' },
        { name: 'A.pdf', path: '_projects/p2/receipts/A.pdf', type: 'file' },
      ] },
      { name: 'ReceiptsOld', path: '_projects/p2/ReceiptsOld', type: 'folder', files: [
        { name: 'old.pdf', path: '_projects/p2/ReceiptsOld/old.pdf', type: 'file' },
      ] },
      { name: 'evidence', path: '_projects/p2/evidence', type: 'folder', files: [
        { name: 'photo_1.jpg', path: '_projects/p2/evidence/photo_1.jpg', type: 'file' },
        { name: 'Photo-2.jpg', path: '_projects/p2/evidence/Photo-2.jpg', type: 'file' },
        { name: 'photo 3.jpg', path: '_projects/p2/evidence/photo 3.jpg', type: 'file' },
      ] },
      { name: 'Empty', path: '_projects/p2/Empty', type: 'folder', files: [] },
    ],
    files: [
      { name: 'z.txt', path: '_projects/p2/z.txt', type: 'file' },
      { name: 'outside.txt', path: 'Other/outside.txt', type: 'file' },
      { name: 'loose.txt', path: 'loose.txt', type: 'file' },
    ],
  },
  noRoot: { folders: [{ name: 'Receipts', path: 'Receipts', type: 'folder', files: [{ name: 'r.pdf', path: 'Receipts/r.pdf', type: 'file' }] }], files: [] },
  empty: { root: '_projects/p3', folders: [], files: [] },
}
for (const [name, l] of Object.entries(listings)) add('projectFileList', { name, listing: l }, ledger.projectFileList(l))
for (const p of ['_projects/p1/Receipts/UPI_slip.pdf', '', null, 'a\\b\\c.pdf', 'plain.pdf', 'dir/']) {
  add('receiptFileName', { path: p }, ledger.receiptFileName(p))
}

// dates.js
for (const v of ['2026-10-12', '2026-10-12T18:30:00Z', '2026-02-30', '2028-02-29', '2027-02-29', '12/10/2026', null, '',
  '2026-13-01', '2026-00-10', '2026-10-00', '0000-01-01', '2026-10-12junk', ' 2026-10-12']) {
  add('dayKeyOf', { value: v }, dates.dayKeyOf(v))
  add('dates.fmtDay', { value: v }, dates.fmtDay(v))
}
for (const m of ['01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12']) add('dates.fmtDay', { value: `2026-${m}-01` }, dates.fmtDay(`2026-${m}-01`))
for (const [a, b] of [['2026-10-12', '2026-10-21'], ['2026-10-12', '2026-10-01'], ['2026-03-28', '2026-04-02'], ['2026-12-31', '2027-01-01'],
  ['', '2026-01-01'], ['2026-01-01', 'x'], ['2024-02-28', '2024-03-01'], ['1900-01-01', '2100-01-01'], ['2026-10-12', '2026-10-12']]) {
  add('daysBetween', { from: a, to: b }, dates.daysBetween(a, b))
}
for (const [d, n] of [['2026-10-12', 7], ['2026-12-28', 7], ['2026-03-01', -1], ['2024-02-28', 1], ['bad', 1], ['2026-10-12', 0], ['2026-10-12', -365], ['2026-10-12', 10000]]) {
  add('addDays', { from: d, n }, dates.addDays(d, n))
}
for (const t of [{ status: 'open', due_date: '2026-10-11' }, { status: 'open', due_date: '2026-10-12' }, { status: 'open', due_date: '2026-10-19' },
  { status: 'open', due_date: '2026-10-20' }, { status: 'open', due_date: '' }, { status: 'open', due_date: '2026-02-30' },
  { status: 'done', due_date: '2026-10-01' }, { status: 'done' }, {}, { status: 'open', due_date: '2026-10-12T20:00:00Z' }]) {
  add('taskBucket', { task: t, today: TODAY }, dates.taskBucket(t, TODAY))
}
for (const [d, done] of [['2026-10-09', false], ['2026-10-12', false], ['2026-10-13', false], ['2026-10-19', false], ['2026-10-20', false],
  ['2026-11-21', false], ['2026-10-09', true], ['', false], ['2025-10-12', false], ['2026-10-14', true], ['2026-02-30', false]]) {
  add('dueInfo', { dueDate: d, today: TODAY, done }, dates.dueInfo(d, TODAY, done))
}
const taskSets = {
  selftest: [
    { id: 'a', status: 'open', kind: 'task', due_date: '2026-10-13', priority: 'normal', created_at: '1' },
    { id: 'b', status: 'open', kind: 'limitation', due_date: '2026-10-18', priority: 'normal', created_at: '2' },
    { id: 'c', status: 'open', kind: 'filing', due_date: '2026-10-13', priority: 'high', created_at: '3' },
    { id: 'd', status: 'open', kind: 'certified_copy', due_date: '2026-10-14', priority: 'low', created_at: '4' },
    { id: 'e', status: 'done', kind: 'limitation', due_date: '2026-10-01', completed_at: '2026-10-02 10:00:00' },
    { id: 'f', status: 'done', kind: 'task', due_date: '2026-10-05', completed_at: '2026-10-10 09:00:00' },
    { id: 'g', status: 'open', kind: 'task', due_date: '', priority: 'high', created_at: '5' },
    { id: 'h', status: 'open', kind: 'compliance', due_date: '2026-09-30', created_at: '6' },
  ],
  ties: [
    { id: 't1', status: 'open', kind: 'task', due_date: '2026-10-15', priority: 'normal', created_at: '2026-10-01 10:00:00' },
    { id: 't2', status: 'open', kind: 'task', due_date: '2026-10-15', priority: 'normal', created_at: '2026-10-01 10:00:00' },
    { id: 't3', status: 'open', kind: 'task', due_date: '2026-10-15', priority: 'weird', created_at: '2026-09-01 10:00:00' },
    { id: 't4', status: 'open', kind: 'task', due_date: '2026-10-15', created_at: '' },
    { id: 't5', status: 'open', kind: 'limitation', due_date: '', created_at: '2026-10-05' },
    { id: 't6', status: 'open', kind: 'certified_copy', due_date: '', priority: 'high' },
    { id: 't7', status: 'done', kind: 'task', updated_at: '2026-10-11 10:00:00' },
    { id: 't8', status: 'done', kind: 'task', completed_at: '', updated_at: '2026-10-11 12:00:00' },
    { id: 't9', status: 'done', kind: 'task' },
    { id: 't10', status: 'open', kind: 'task', due_date: '2026-10-25', priority: 'low' },
    { id: 't11', status: 'open', kind: 'limitation', due_date: '2026-10-25', priority: 'low' },
    { id: 't12', status: 'open', kind: 'task', due_date: '2026-10-25', priority: 'high' },
  ],
  empty: [],
}
for (const [name, list] of Object.entries(taskSets)) {
  const g = dates.groupTasks(list, TODAY)
  add('groupTasks', { name, tasks: list, today: TODAY }, Object.fromEntries(Object.entries(g).map(([k, v]) => [k, v.map(t => t.id)])))
  for (const a of list) for (const b of list) add('compareTasks', { a, b }, Math.sign(dates.compareTasks(a, b)))
}

// receipt.js
for (const p of [{ case_number: 'CS(OS) 55', case_year: '2018' }, { case_type: 'W.P.(C)', case_number: '1234', case_year: '2024' },
  { case_type: 'W.P.(C)', case_number: 'W.P.(C) 1234/2024', case_year: '2024' }, { case_year: '2024' },
  { case_type: 'crl.a.', case_number: 'CRL.A. 9', case_year: '' }, { case_type: '  W.P.  ', case_number: '  12  ', case_year: ' 2020 ' }, {}]) {
  add('receipt.caseNumberOf', { project: p }, receipt.caseNumberOf(p))
}
const people = [
  { role: 'opposite_party', name: 'Vinod Kumari', address: 'Elsewhere' },
  { role: 'client', name: 'Mr. Director', address: 'Board room' },
  { role: 'client', name: 'ankit bhalla', address: '12 Lajpat Nagar,\n New Delhi' },
]
for (const [p, ppl] of [[{ client: 'Ankit Bhalla' }, people], [{ client: 'ABC Pvt Ltd' }, people], [{ client: '' }, people], [{}, []],
  [{ client: '  Ankit   Bhalla ' }, people], [{}, [{ role: 'client', name: '  ' }, { role: 'client', name: 'B', address: null }]]]) {
  add('receiptClient', { project: p, people: ppl }, receipt.receiptClient(p, ppl))
}
const profiles = [
  { name: ' Asha  Rao ', title: 'Advocate, Delhi High Court', organization: 'Rao Chambers', phone: '+919876543210', email: 'a@x.in' },
  { phone: '011-2345 6789' }, {}, { name: 'X', phone: '98765 43210' }, { phone: '12345' },
]
for (const u of profiles) add('advocateFromProfile', { user: u }, receipt.advocateFromProfile(u))
for (const p of [{ name: ' Bhalla  v. Kumari ', case_number: 'CS(OS) 55', case_year: '2018', forum_name: 'Delhi High Court' }, {}]) {
  add('matterFromProject', { project: p }, receipt.matterFromProject(p))
}
const receiptCases = {
  selftestCheque: {
    advocate: receipt.advocateFromProfile({ name: 'Asha Rao', title: 'Advocate', organization: 'Rao <Chambers>', email: 'a@x.in' }),
    client: { name: 'Ankit "AB" Bhalla', address: '' },
    matter: receipt.matterFromProject({ name: 'Bhalla v. Kumari <script>alert(1)</script>', case_number: 'CS(OS) 55', case_year: '2018', forum_name: 'Delhi High Court' }),
    entry: { id: 'pl_1760270000000_ab12cd', kind: 'payment', amount_paise: 2500000, entry_date: '2026-10-12', mode: 'cheque', reference: '004512, HDFC Bank', title: '' },
  },
  cashAtLimit: { entry: { id: 'x', amount_paise: 500000, entry_date: '2026-10-12', mode: 'cash', title: 'Advance fee' } },
  upiWithAddress: {
    advocate: receipt.advocateFromProfile({ name: 'Asha Rao', title: '', organization: '', phone: '9876543210', email: 'asha@rao.in' }),
    client: { name: "O'Neil & Sons", address: '4, Park St, Kolkata' },
    matter: receipt.matterFromProject({ name: 'Neil v. State', forum_name: 'the Calcutta High Court' }),
    entry: { id: 'pl_1_UPI999', kind: 'payment', amount: 5000.01, entry_date: '2026-03-31', mode: 'upi', reference: ' 412345678901 ', title: 'Appearance fee' },
  },
  noClient: {
    advocate: receipt.advocateFromProfile({ email: 'only@mail.in' }),
    matter: receipt.matterFromProject({}),
    entry: { id: '', amount_paise: 75, mode: 'card', reference: 'TXN1' },
  },
  scriptInNames: {
    advocate: receipt.advocateFromProfile({ name: '<script>x</script>', title: '<b>Sr. Advocate</b>', organization: "A's & B's" }),
    client: { name: '<img src=x onerror=alert(1)>', address: '"><script>' },
    matter: receipt.matterFromProject({ name: '</title><script>', case_type: '<W.P.>', case_number: '1', forum_name: '<Court>' }),
    entry: { id: 'z', amount_paise: 12345678901, entry_date: '2026-10-12', mode: 'other', reference: '<ref>', title: '<towards>' },
  },
  bankNoRef: {
    advocate: { name: 'Advocate One', designation: '', chambers: 'Chambers', phone: '', email: '' },
    client: { name: 'Client', address: '' },
    matter: { title: 'Matter', caseNo: '', forum: '' },
    entry: { id: 'pl_bank', amount_paise: 500001, entry_date: '2026-02-30', mode: 'bank', reference: '' },
  },
  otherModeNoRef: { entry: { id: 'q', amount: 1, mode: 'nonsense' } },
}
for (const [name, args] of Object.entries(receiptCases)) add('buildReceiptHtml', { name, ...args }, receipt.buildReceiptHtml(args))

// rules.js — text and vocabulary
// Text only: the app's fields are strings, so the web's "must be text" refusal has no counterpart.
for (const [v, label, max] of [[null, 'client', 300], ['  x  ', 'client', 300], ['   ', 'client', 300], ['abcd', 'x', 3], ['abc', 'x', 3],
  ['\u0928\u094d\u092f\u093e', 'x', 3], ['\u{1F600}\u{1F600}', 'x', 3], ['\u00a0 y \u3000', 'stage', 200]]) {
  add('optText', { value: v, label, max }, attempt(() => rules.optText(v, label, max)))
  add('reqText', { value: v, label, max }, attempt(() => rules.reqText(v, label, max)))
}
for (const [v, allowed, label, fallback] of [['Hearing', rules.UPDATE_KINDS, 'kind', 'note'], ['', rules.UPDATE_KINDS, 'kind', 'note'],
  [' ', rules.PRIORITIES, 'priority', 'normal'], ['urgent', rules.PRIORITIES, 'priority', 'normal'], [null, rules.LEDGER_KINDS, 'kind', null],
['  FEE ', rules.LEDGER_KINDS, 'kind', null], ['closed', rules.PROJECT_STATUSES, 'status', 'active']]) {
  add('oneOf', { value: v, allowed, label, fallback }, attempt(() => rules.oneOf(v, allowed, label, fallback)))
}
// Dates
for (const ms of [Date.parse('2026-10-12T19:00:00Z'), Date.parse('2026-10-12T18:29:59Z'), Date.parse('2026-10-12T18:30:00Z'), 0, Date.parse('2026-12-31T18:30:00Z')]) {
  add('istDay', { at: ms }, rules.istDay(ms))
}
const dateInputs = ['2026-10-20', '05-01-2024', '5/1/2024', '5.1.2024', '2026-10-12T20:00:00.000Z', '2026-10-12T18:29:59Z', '2026-02-30',
  '31-04-2026', 'next Tuesday', '', null, ' 2026-10-20 ', '1799-12-31', '2201-01-01', '29/02/2028', '29/02/2027', '2026-10-12T10:00:00+05:30',
  '2026-10-12T23:00:00-05:00', '2026-10-12T20:00', '2026-10-12T24:00:00Z', '2026-10-12Tjunk', '2026-02-30T10:00Z', '123-45-6789',
  '2026/10/12', '1-1-2026', '2026-10-12 10:00:00', '2026-10-12T10:00:00z', '2026-10-12T10:00:00.5Z', '2026-10-12T25:00Z']
for (const v of dateInputs) add('istDateOf', { value: v }, rules.istDateOf(v))
for (const v of ['20/10/2026', '', '  ', null, 'soon', '2026-10-12T20:00:00Z', '2026-02-30']) {
  add('dayOf', { value: v, label: 'dueDate' }, attempt(() => rules.dayOf(v, 'dueDate')))
}
for (const v of ['2019', '2019-03', '2019-13', '1799', '2201', '2026-10-12', '12-10-2026', '2026-10-12T20:00:00Z', '2026-10-12T10:00:00+05:30',
  '2026-10-12T99:00:00Z', '', null, 'March 2019', '2019-00', '2026-10-12T20:00']) {
  add('eventDateOf', { value: v, label: 'eventDate' }, attempt(() => rules.eventDateOf(v, 'eventDate')))
}
for (const [v, today] of [['2026-10-12', TODAY], ['2026-10-11', TODAY], ['2026-10-11T19:00:00Z', TODAY], ['junk', TODAY], [null, TODAY],
  ['2026-10-12', rules.istDay(Date.parse('2026-10-12T09:00:00Z'))], ['13-10-2026', TODAY]]) {
  add('isTodayOrLaterIst', { value: v, today }, rules.isTodayOrLaterIst(v, today))
}
const nextHearingCases = [
  { hearings: ['2026-11-01', '2026-10-20', '2026-09-01'] },
  { stored: '2026-09-01', hearings: ['2026-10-12'] },
  { stored: '2026-10-15', hearings: ['2026-11-01'] },
  { stored: '2026-09-01', hearings: ['2026-11-01'] },
  { stored: '2026-09-01', hearings: [] },
  { stored: '2026-10-20', removed: '2026-10-20', hearings: ['2026-11-05'] },
  { stored: '2026-10-20', removed: '2026-10-20', hearings: [] },
  { stored: '2026-10-20', removed: '2026-10-20', hearings: ['2026-12-01'] },
  { stored: '2026-10-20', removed: '2026-10-20', hearings: ['2026-10-20'] },
  { stored: null, hearings: [], caseNext: '2026-10-30' },
  { stored: '2026-10-25T10:00:00.000Z', hearings: [] },
  {},
  { hearings: ['junk', '', null, '2026-02-30'] },
  { caseNext: '2026-10-01' },
  { caseNext: '2026-10-01', stored: '2026-09-01' },
  { stored: '2026-10-12T19:00:00Z' },
  { stored: '12-11-2026', hearings: ['13/11/2026'] },
  { stored: '2026-11-01', removed: '01-11-2026' },
  { stored: '2026-09-01', removed: '2026-09-01', hearings: ['2026-08-01'] },
  { stored: '2026-10-11', hearings: ['2026-10-11T19:00:00Z'] },
  { hearings: ['2026-10-12'], caseNext: '2026-10-12', stored: '2026-10-12' },
  { hearings: ['2027-01-01'], caseNext: '2026-12-31' },
  { hearings: ['2026-10-11'], caseNext: '2026-10-10' },
  { stored: 'junk', hearings: [] },
  { stored: 'junk', hearings: ['2026-10-13'] },
  { removed: '2026-10-13', hearings: ['2026-10-13'] },
  { stored: '2026-10-13', removed: '2026-10-13', caseNext: '2026-10-13' },
  { stored: '2026-10-20', removed: '2026-10-21', hearings: ['2026-10-21'] },
  { hearings: ['2026-10-12T18:29:59Z', '2026-10-12T18:30:00Z'] },
  { stored: '2026-09-30', removed: '2026-09-30', caseNext: '2026-09-29' },
]
for (const c of nextHearingCases) add('computeNextHearing', { ...c, today: TODAY }, rules.computeNextHearing({ ...c, today: TODAY }))
// Money
for (const n of [1500, 0.29, 1.005, 0, -5, NaN, Infinity, 1e12, 1e11, 1e11 + 1, 0.001, 0.005, 2.675, 123456.789, 99999999999.99]) {
  add('rupeesToPaise.number', { amount: num(n) }, attempt(() => rules.rupeesToPaise(n)))
}
for (const s of ['1,50,000.50', '₹ 2,000', 'five hundred', '', '0', '0.00', '-5', '1.', '.5', '100000000001', '1 0 0', '1.005', '₹₹1']) {
  add('rupeesToPaise.text', { amount: s }, attempt(() => rules.rupeesToPaise(s)))
}
add('rupeesToPaise.text', { amount: 'x', label: 'Fee' }, attempt(() => rules.rupeesToPaise('x', 'Fee')))
for (const p of [15000050, 29, 0, -150, 1]) add('paiseToRupees', { paise: p }, rules.paiseToRupees(p))
for (const rows of [
  [{ kind: 'fee', amount_paise: 5000000 }, { kind: 'fee', amount_paise: 2500050 }, { kind: 'payment', amount_paise: 3000000 }, { kind: 'expense', amount_paise: 120000 }],
  [{ kind: 'payment', amount_paise: 100 }], [], [{ kind: 'other', amount_paise: 100 }, { kind: 'fee', amount_paise: 1 }],
]) add('rules.ledgerTotals', { rows }, rules.ledgerTotals(rows))
// Projects
for (const v of ['TEAL', ' image ', '#ff0000', '', null, 'Navy', 'sand']) add('bannerOf', { value: v }, rules.bannerOf(v))
for (const v of ['Accused', 'Proforma respondent', '  ', null, 'x'.repeat(61), ' OTHER ', 'other side']) {
  add('ourSideOf', { value: v }, attempt(() => rules.ourSideOf(v)))
}
for (const [n, c] of [['Sharma v. State', 'Sharma v. State'], ['Sharma v. State', 'sharma v. state'], ['Sharma v. State', 'Sharma v. State '],
  ['Sharma v. State', null], ['', ''], [null, ''], [null, 'null'], ['x', 'x']]) {
  add('confirmMatches', { name: n, confirm: c }, rules.confirmMatches(n, c))
}
const kase = { court_type: 'hc', court_name: 'Delhi High Court', case_type: 'W.P.(C)', case_number: '1234', case_year: '2025',
  cnr: null, diary_number: '52650/2025', next_hearing_date: '2026-11-03' }
const fillCases = [
  [{ forum_type: 'other', forum_name: '', case_number: 'typed by user', cnr: null, next_hearing_date: null }, kase],
  [{ next_hearing_date: '2026-10-01' }, kase],
  [{}, { court_type: 'forum', court_name: ' District Consumer Forum ', cnr: 'MHCF01', next_hearing_date: '2026-10-12T20:00:00Z' }],
  [{ forum_type: 'district' }, { court_type: 'sc', court_name: 'Supreme Court of India', case_number: '  ', diary_number: '' }],
  [{ forum_type: '' }, { court_type: 'nclt', case_year: '2024', next_hearing_date: 'junk' }],
  [{ forum_name: 'X', case_type: 'Y', case_year: '1', cnr: 'Z' }, { court_type: 'unknown', court_name: 'N', case_type: 'T', case_year: '2', cnr: 'C' }],
]
for (const [p, k] of fillCases) add('fieldsFromCase', { project: p, kase: k }, rules.fieldsFromCase(p, k))
const unlinkCases = [
  [{ forum_type: 'high_court', forum_name: 'Delhi High Court', case_type: 'W.P.(C)', case_number: 'typed by user', case_year: '2025', cnr: '52650/2025', next_hearing_date: '2026-11-03' }, kase],
  [{ forum_name: 'Bombay High Court' }, kase],
  [{ forum_type: 'tribunal', forum_name: ' NCLT ', cnr: 'C1' }, { court_type: 'nclt', court_name: 'NCLT', cnr: 'C1 ' }],
  [{ forum_type: 'other', forum_name: 'Court', next_hearing_date: '2026-11-03' }, { court_type: 'hc', court_name: 'Court', next_hearing_date: '2026-11-03T05:00:00Z' }],
  [{ case_number: '', case_year: null }, { case_number: '', case_year: null }],
]
for (const [p, k] of unlinkCases) add('fieldsClearedOnUnlink', { project: p, kase: k }, rules.fieldsClearedOnUnlink(p, k))
const practiceCases = [
  ['ARB.P.', 'hc'], ['CRL.M.C.', 'hc'], ['W.P.(C)', 'hc'], ['CS(COMM)', 'hc'], ['CP(IB)', 'nclt'], ['CC', 'forum'], ['XYZ', 'hc'],
  ['CRL.A.', 'hc'], ['O.M.P.(COMM)', 'hc'], ['OMP (I) (COMM.)', 'hc'], ['CS(OS)', 'hc'], ['MAT.APP.(F.C.)', 'hc'], ['ITA', 'hc'],
  ['CO.PET.', 'hc'], ['LPA', 'hc'], ['SLP(C)', 'sc'], ['SLP(CRL)', 'sc'], ['BAIL APPLN.', 'hc'], ['BA', 'district'], ['ABA', 'hc'],
  ['CRL.REV.P.', 'hc'], ['SC', 'district'], ['CC', 'district'], ['N.I. ACT', 'district'], ['MCRC', 'hc'], ['CRLMC', 'hc'],
  ['CONT.CAS(C)', 'hc'], ['W.P.(CRL)', 'hc'], ['HMA', 'district'], ['GP', 'district'], ['MAINT', 'district'], ['TM', 'hc'],
  ['C.O.(COMM.IPD-TM)', 'hc'], ['GSTR', 'hc'], ['CUSAA', 'hc'], ['SERV.TAX', 'hc'], ['C.A.(CAA)', 'nclt'], ['COMP.APP', 'nclat'],
  ['IB', 'hc'], ['LAB', 'district'], ['I.D.', 'district'], ['RFA', 'hc'], ['RSA', 'hc'], ['FAO', 'hc'], ['CRP', 'hc'], ['EX.P.', 'hc'],
  ['EX.P.(COMM)', 'hc'], ['O.S.', 'district'], ['CIVIL SUIT', 'district'], ['SEC.9', 'district'], ['SECTION 34', 'district'],
  ['w.p.(c)', 'hc'], ['', 'hc'], ['', ''], [null, null], ['APPEAL', 'tribunal'], ['DIVORCE PETITION', 'district'], ['EMP', 'district'],
]
for (const [t, c] of practiceCases) add('practiceAreaFromCase', { case_type: t, court_type: c }, rules.practiceAreaFromCase({ case_type: t, court_type: c }))
const nameCases = [
  { title: 'TATA CAPITAL LTD vs. MANOJ BHADANA' },
  { title: 'M/S NEW DELHI TYRE HOUSE vs. STATE NCT OF DELHI AND ANR.' },
  { title: 'Sharma vs. Delhi Development Authority' },
  { title: 'K. V. RAO vs. STATE OF U.P.' },
  { title: '', case_type: 'CP(IB)', case_number: '12', case_year: '2025' },
  { title: '   ', case_type: 'W.P.(C)', case_number: '5' },
  { title: null, case_number: '7', case_year: '2020' },
  { title: '', case_type: 'LPA' },
  {},
  { title: 'STATE VS. RAM' }, { title: 'STATE V. RAM KUMAR' }, { title: 'STATE V RAM' }, { title: 'M/S. ABC PVT. LTD. VERSUS UOI AND ORS.' },
  { title: 'RAM KUMAR ANR. vs. SHYAM' }, { title: `${'LONG NAME '.repeat(25)}vs. STATE` },
  { title: 'ram  lal\n vs.   shyam' }, { title: 'A vs. B' }, { title: 'ABC LTD. V/S. XYZ LTD.' }, { title: 'V. K. SINGH vs. UOI' },
  { title: '\u0930\u093e\u092e \u092c\u0928\u093e\u092e \u0936\u094d\u092f\u093e\u092e', case_number: '1' },
]
for (const k of nameCases) add('matterNameFromCase', { kase: k }, rules.matterNameFromCase(k))
for (const [v, pid] of [['Receipts/r 1.pdf', 'prj_1'], ['_projects/prj_1/Receipts/r.pdf', 'prj_1'], ['_projects/prj_2/Receipts/r.pdf', 'prj_1'],
  ['../../etc/passwd', 'prj_1'], ['/etc/passwd', 'prj_1'], ['\\x', 'prj_1'], ['', 'prj_1'], [null, 'prj_1'], ['_projects/prj_1', 'prj_1'],
  ['./Receipts//\u0930.pdf', 'prj_1'], ['Receipts\\sub\\a b.pdf', 'prj_1'], ['_projects/prj_1/./x', 'prj_1'], ['Receipts/.../x', 'prj_1'],
  ['_PROJECTS/prj_1/x', 'prj_1'], [`${'a'.repeat(501)}`, 'prj_1']]) {
  add('receiptPathOf', { value: v, projectId: pid }, attempt(() => rules.receiptPathOf(v, pid)))
}
for (const e of ['a@b.co', 'not-an-email', 'a b@c.d', 'a@b', '  a@b.in  ', '', '@b.c', 'a@@b.c']) {
  add('validEmail', { value: e }, !attempt(() => rules.personColumns({ email: e })).error)
}
for (const p of ['+91 98100 12345', 'call me', '(011) 2338-1234 ext. 12', '12', '123', '011.2345.678 x 9', '98100-12345x', '', ' + 1 2 3 ', '+91 98100 12345 ext12']) {
  add('validPhone', { value: p }, !attempt(() => rules.personColumns({ phone: p })).error)
}
for (const [last, now] of [[null, 1000], [1000, 61000], [1000, 1000 + rules.CASE_REFRESH_GAP_MS], [1000, 1001], [1000, 300999], [1000, 300000]]) {
  add('refreshWaitSeconds', { lastAt: last, now }, rules.refreshWaitSeconds(last, now))
}

// projectRecord.js
for (const v of ['2026-10-12', '2026-10-12T19:00:00Z', '2026-10-12 19:00:00', '2019', '2019-03', '', null, 'junk', '2026-02-30', ' 2026-10-12 ',
  '2026-10-12T10:00:00+05:30', '2026-10-12T18:29:59.999Z']) {
  add('record.dayKey', { value: v }, record.dayKey(v))
  add('record.fmtDay', { value: v }, record.fmtDay(v))
  add('fmtDots', { value: v }, record.fmtDots(v))
  add('weekdayOf', { value: v }, record.weekdayOf(v))
  add('daysFromToday', { value: v, today: TODAY }, record.daysFromToday(v, TODAY))
}
for (const n of [null, 0, 1, -1, 2, -2, 30]) add('relDays', { n }, record.relDays(n))
for (const s of ['05-01-2024', '2024-01-05', '2024-1-5', '5/1/2024', '5.1.2024', '31-04-2026', '2026-02-30', 'Jan 5 2024', '', null, '2024-01-05T10:00:00Z',
  '05-01-24', ' 05-01-2024 ', '2024-13-01', '29.02.2028']) add('parseDocDate', { value: s }, record.parseDocDate(s))
for (const t of ['O', 'j', 'OJ', ' Order dated 01.01.2026 ', '', null, 'Judgment']) add('orderTitle', { raw: t }, record.orderTitle(t))
for (const t of ['TO BE LISTED IN COURT NO.42', 'LISTED BEFORE COURT NO. 94)', 'Court no 5 at 10:30', 'AB', '', null, 'FRESH (FOR ADMISSION)',
  'IN COURT NO.3 ITEM 7))', 'ADJOURNED', 'Listed in courtno.12']) add('plainCourtText', { raw: t }, record.plainCourtText(t))
const court = [
  { id: 'h1', section: 'hearings', title: 'Listing', item_date: '2026-09-01', data: { courtNo: '42', itemNo: 7, time: '10:30 AM', coram: 'HON\'BLE MR. JUSTICE X', listType: 'Supplementary List', nextDate: '2026-10-20' } },
  { id: 'h2', section: 'hearings', title: 'FOR ARGUMENTS', subtitle: 'Bench of Justice Y', item_date: '2026-10-20', data: '{"courtNo":"COURT NO. 5","remarks":"  Part   heard ","bench":"B"}' },
  { id: 'h3', section: 'hearings', title: '', item_date: '2026-11-15T20:00:00Z', data: { purpose: 'Final hearing', courtNo: 'IV', bench: 'Division Bench' } },
  { id: 'h4', section: 'hearings', title: 'Mention', item_date: '', data: {} },
  { id: 'o1', section: 'orders', title: 'O', item_date: '2026-09-01', data: { type: 'Order', url: 'https://x' } },
  { id: 'o2', section: 'orders', title: '', item_date: '2026-10-20', data: { title: 'J', type: 'Interim order' } },
  { id: 'o3', section: 'orders', title: 'Order dated 15.07.2026', item_date: '2026-07-15', data: 'not json' },
  { id: 'o4', section: 'orders', title: 'Order', item_date: null, data: null },
  { id: 'x1', section: 'parties', title: 'Petitioner', item_date: '2026-01-01', data: {} },
]
for (const it of court.filter(i => i.section === 'hearings')) add('hearingFacts', { item: it }, record.hearingFacts(it))
add('ordersOf', { court }, record.ordersOf(court).map(it => it.id))
add('ordersOf', { court: [] }, [])
const updates = [
  { id: 'u1', kind: 'event', title: '  Agreement   signed ', body: ' Between the parties. ', event_date: '2019-03', created_at: '2026-10-01 10:00:00', source: 'manual' },
  { id: 'u2', kind: 'hearing', title: 'Listed — FOR ARGUMENTS', body: '', event_date: '2026-10-20', created_at: '2026-10-02 10:00:00', source: 'court' },
  { id: 'u3', kind: null, title: '', body: 'A note with no title', event_date: null, created_at: '2026-10-11T19:30:00.000Z', source: null },
  { id: 'u4', kind: 'filing', title: 'Reply filed.', body: 'Copy served', event_date: '2026-09-01', created_at: '2026-09-01 08:00:00', source: 'ai', source_ref: ' doc.pdf p.3 ' },
  { id: 'u5', kind: 'milestone', title: 'Admitted', body: null, event_date: '2026-09-01', created_at: '2026-09-01 07:00:00', source: 'manual' },
  { id: 'u6', kind: 'order', title: 'Order passed', body: '', event_date: '2026-10-20', created_at: '', source: 'court' },
  { id: 'u7', kind: 'note', title: '', body: '', event_date: '', created_at: '', source: 'manual' },
  { id: 'u8', kind: 'event', title: 'Year only', body: '', event_date: '2019', created_at: '2026-10-03 10:00:00', source: 'manual' },
]
const chronoSets = {
  full: [updates, court],
  ownOnly: [updates, []],
  courtOnly: [[], court],
  empty: [[], []],
  dedupe: [[{ id: 'd1', kind: 'hearing', title: 'listed for arguments', event_date: '2026-10-20', source: 'court' }],
    [{ id: 'dh', section: 'hearings', title: 'FOR ARGUMENTS', item_date: '2026-10-20', data: {} }]],
  dedupeMiss: [[{ id: 'd1', kind: 'hearing', title: 'Listed — FOR ARGUMENTS', event_date: '2026-10-21', source: 'court' }],
    [{ id: 'dh', section: 'hearings', title: 'FOR ARGUMENTS', item_date: '2026-10-20', data: {} }]],
  dedupeManual: [[{ id: 'd1', kind: 'hearing', title: 'Listed — FOR ARGUMENTS', event_date: '2026-10-20', source: 'manual' }],
    [{ id: 'dh', section: 'hearings', title: 'FOR ARGUMENTS', item_date: '2026-10-20', data: {} }]],
  orderDedupe: [[{ id: 'd2', kind: 'order', title: 'JUDGMENT', event_date: '2026-10-20T05:00:00Z', source: 'court' }],
    [{ id: 'do', section: 'orders', title: 'J', item_date: '2026-10-20', data: {} }]],
  listingPurpose: [[], [{ id: 'l1', section: 'hearings', title: 'listing', item_date: '2026-10-01', data: { courtNo: '-', time: '' } },
    { id: 'l2', section: 'hearings', title: null, item_date: '2026-10-02', data: { purpose: 'Listing' } }]],
  orderTypes: [[], [{ id: 'ot1', section: 'orders', title: '', item_date: '2026-10-01', data: { type: 'ORDER' } },
    { id: 'ot2', section: 'orders', title: 'Daily order', item_date: '2026-10-01', data: { type: 'Final' } },
    { id: 'ot3', section: 'orders', item_date: '2026-10-02', data: {} }]],
  timestampsOnly: [[{ id: 't1', kind: 'note', title: 'Late night', created_at: '2026-10-11 19:00:00', source: 'manual' },
    { id: 't2', kind: 'note', title: 'Morning', created_at: '2026-10-11 02:00:00', source: 'manual' }], []],
}
for (const [name, [u, c]] of Object.entries(chronoSets)) {
  const entries = record.chronologyEntries(u, c)
  const shape = (es) => es.map(e => ({ key: e.key, id: e.id, src: e.src, own: e.own, kind: e.kind, day: e.day, title: e.title, body: e.body, sourceRef: e.sourceRef, created: e.created }))
  add('chronologyEntries', { name, updates: u, court: c }, shape(entries))
  add('sortChronology', { name, updates: u, court: c, newestFirst: false }, record.sortChronology(entries, false).map(e => e.key))
  add('sortChronology', { name, updates: u, court: c, newestFirst: true }, record.sortChronology(entries, true).map(e => e.key))
  add('eventText', { name, updates: u, court: c }, entries.map(e => record.eventText(e)))
}
// More chronology variations, so the merge is held to more than one shape.
for (let i = 0; i < 14; i++) {
  const u = updates.filter((_, j) => (j + i) % 3 !== 0).map(x => ({ ...x, source: ['manual', 'ai', 'court', null][(i + x.id.length) % 4] }))
  const c = court.filter((_, j) => (j * 7 + i) % 4 !== 1)
  const entries = record.chronologyEntries(u, c)
  add('chronologyEntries', { name: `variant${i}`, updates: u, court: c },
    entries.map(e => ({ key: e.key, id: e.id, src: e.src, own: e.own, kind: e.kind, day: e.day, title: e.title, body: e.body, sourceRef: e.sourceRef, created: e.created })))
}
const nextCases = [
  [{ next_hearing_date: '2026-10-20' }, { next_hearing_date: '2026-10-25' }, court],
  [{ next_hearing_date: '2026-10-25' }, { next_hearing_date: '2026-10-20' }, court],
  [{ next_hearing_date: '2026-10-20' }, { next_hearing_date: '2026-10-20' }, court],
  [{ next_hearing_date: '2026-09-01' }, { next_hearing_date: '2026-08-01' }, court],
  [{}, {}, court],
  [{ next_hearing_date: '2026-11-01' }, null, court],
  [{ next_hearing_date: '2026-11-16' }, null, court],
  [{ next_hearing_date: '2026-10-12' }, null, []],
  [null, { next_hearing_date: '2026-10-11T20:00:00Z' }, court],
  [{ next_hearing_date: '2026-09-01' }, { next_hearing_date: '2026-09-01' }, court],
  [{ next_hearing_date: '2026-10-11' }, { next_hearing_date: '2026-09-30' }, []],
]
for (const [p, lc, ch] of nextCases) {
  const r = record.nextHearing({ project: p, linkedCase: lc, courtHistory: ch }, TODAY)
  add('nextHearing', { project: p, linkedCase: lc, court: ch, today: TODAY },
    r && { day: r.day, from: r.from, days: r.days, listing: r.listing?.id ?? null, latest: r.latest?.id ?? null })
}
for (const v of ['petitioner', 'other', 'Intervener', '', null, 'respondent']) {
  add('record.ourSideLabel', { side: v }, record.ourSideLabel(v))
  add('meta.ourSideLabel', { side: v }, meta.ourSideLabel(v))
}
for (const p of [{ case_number: '1234', case_type: 'W.P.(C)', case_year: '2026' }, { case_number: 'CS(OS) 55', case_type: 'CS(OS)', case_year: 2018 },
  { case_number: '', case_type: 'X' }, { case_number: ' 12 ', case_type: '', case_year: '' }, {}]) {
  add('caseNoLabel', { project: p }, record.caseNoLabel(p))
}
for (const v of ['DLHC010012342026', '342339/2026', ' 342339 / 2026 ', '12/26', '', null]) add('cnrLabel', { value: v }, record.cnrLabel(v))
const lodProjects = [
  [{ name: 'Sharma v. State', forum_name: 'High Court of Delhi', case_type: 'W.P.(C)', case_number: '1234', case_year: '2026', client: 'Ram Sharma', opposite_party: 'State <NCT>', our_side: 'petitioner' }, null, 'full'],
  [{ name: 'Accused & Co', client: 'A', opposite_party: 'B', our_side: 'Accused' }, { court_name: 'Saket Courts', case_type: 'SC', case_number: 'SC No. 45', case_year: '2024' }, 'ownOnly'],
  [{ name: '', our_side: 'other', client: 'A', opposite_party: 'B' }, { court_name: 'Bombay HC', case_number: 'ABC' }, 'courtOnly'],
  [{}, null, 'empty'],
  [{ name: 'Respondent side', client: 'Us', opposite_party: 'Them', our_side: 'respondent', case_number: 'CS(OS) 55/2018', case_type: 'cs(os)' }, null, 'dedupe'],
]
for (const [p, lc, setName] of lodProjects) {
  const [u, c] = chronoSets[setName]
  add('listOfDatesHtml', { project: p, linkedCase: lc, updates: u, court: c },
    record.listOfDatesHtml({ project: p, linkedCase: lc, entries: record.chronologyEntries(u, c) }))
}
for (const l of [[{ kind: 'fee', amount: 100.1 }, { kind: 'fee', amount_paise: 20 }, { kind: 'payment', amount: 50 }, { kind: 'expense', amount: '7.5' },
  { kind: 'expense', amount: 'x' }, { kind: 'other', amount: 5 }], []]) add('totalsFromLedger', { ledger: l }, record.totalsFromLedger(l))

// projectMeta.js
for (const p of [{ banner: 'teal' }, { banner: 'image', color: 'amber' }, { banner: 'nonsense', color: 'violet' }, {}, { color: 'sky' },
  { color: 'red' }, { banner: 'NAVY' }, null]) add('bannerPresetOf', { project: p }, meta.bannerPresetOf(p))
for (const k of ['civil', 'writ', 'labour', 'maritime', '', null]) add('practiceAreaLabel', { key: k }, meta.practiceAreaLabel(k))
for (const p of [{ case_number: '4412', case_type: 'W.P.(C)', case_year: '2025' }, { case_number: '4412' }, { cnr: 'DLHC01' }, {},
  { case_number: '', cnr: 'X', case_type: 'T' }, { case_number: 'CS(OS) 55', case_type: 'CS(OS)' }]) add('caseRefOf', { project: p }, meta.caseRefOf(p))
for (const p of [{ updated_at: '2026-10-01 10:00:00', created_at: '2026-09-01 10:00:00' },
  { updated_at: '2026-09-01 10:00:00', created_at: '2026-08-01T00:00:00.000Z', last_activity: '2026-10-05' },
  { updated_at: '2026-09-01 10:00:00', last_activity: '2999-01-01' }, {}, { created_at: 'junk', last_activity: '2026-01-01T05:30:00+05:30' }]) {
  add('activityAt', { project: p }, meta.activityAt(p))
}

// trackedCases.js
for (const s of ['Pending', 'Disposed', 'DECIDED', 'dismissed in default', 'Closed', 'withdrawn', '', null]) {
  add('caseStatusKey', { status: s }, tracked.caseStatusKey({ status: s }))
}
for (const id of ['', '1', '42', 'case_17602', 'abc-def-ghi', '\u0928\u094d\u092f\u093e\u092f', '\u{1F4D4}x', 'a'.repeat(300),
  'c_1760270000000_ab12cd', '0', 'CASE', 'case']) add('bannerForCase', { caseId: id }, tracked.bannerForCase(id))
const projectsForMatch = [
  { id: 'p1', linked_case_id: 'c1', created_at: '2026-09-01 10:00:00' },
  { id: 'p2', linked_case_id: 'c1', created_at: '2026-08-01 10:00:00' },
  { id: 'p3', linked_case_id: 'c2', created_at: '2026-08-01 10:00:00' },
  { id: 'p4', linked_case_id: 'c2', created_at: '2026-08-01 10:00:00' },
  { id: 'p5', linked_case_id: '', created_at: '2020-01-01' },
  { id: 'p6', linked_case_id: null },
  { id: 'p7', linked_case_id: 'c3' },
  { id: 'p8', linked_case_id: 'c3', created_at: '2026-01-01' },
  { id: 'p9', linked_case_id: 'c4', created_at: '2026-10-01T00:00:00.000Z' },
  { id: 'p10', linked_case_id: 'c4', created_at: '2026-10-01 00:00:00' },
]
add('matterByCase', { projects: projectsForMatch }, Object.fromEntries([...tracked.matterByCase(projectsForMatch)].map(([k, v]) => [k, v.id])))
const teams = new Map([[1, { name: 'Firm', member_count: 3 }], [2, { name: 'Solo', member_count: 1 }]])
for (const k of [
  { id: 7, title: 'TATA CAPITAL LTD vs. MANOJ BHADANA', status: 'Pending', court_name: 'Delhi High Court', case_type: 'W.P.(C)', case_number: '12', case_year: '2025', team_id: 1, created_at: '2026-01-01' },
  { id: 'c8', parties: 'A v. B', status: 'Disposed', court_type: 'sc', diary_number: '342/2026', team_id: 2 },
  { id: 'c9', court_type: 'nclat', cnr: 'X1', team_id: 9, team_name: 'Gone' },
  { id: 'c10', diary_number: '55/2026' },
  { id: 'c11' },
  { id: 'c12', court_type: 'unknown', case_number: '4', team_id: 1, team_name: 'Fallback' },
]) {
  const r = tracked.trackedCaseRow(k, teams)
  add('trackedCaseRow', { kase: k, team: teams.get(k.team_id) ?? null }, r)
}

// trackCase.js
const pickA = { courtType: 'hc', courtCode: 'DLHC', courtName: 'Delhi High Court', caseType: 'W.P.(C)', caseNumber: '1234', caseYear: '2025', cnr: 'DLHC010012342025', title: 'A vs. B' }
for (const p of [pickA, { courtType: 'sc', diaryNumber: '342/2026', title: 'X' }, {}, { caseNumber: '5', parties: 'P', judge: 'J', status: 'S', stage: 'T', nextHearingDate: '2026-10-20', scrapeRef: 'R' }]) {
  add('casePayload', { pick: p }, trackCase.casePayload(p))
  add('extIdOf', { body: trackCase.casePayload(p) }, extIdOf(trackCase.casePayload(p)))
}
for (const s of ['DLHC-01/2025', 'w.p.(c) 12', '', null, '\u0928\u094d\u092f\u093e\u092f 1', ' a b ']) add('canon', { value: s }, canon(s))
const trackedRows = [
  { id: 'c1', team_id: 'tA', ext_id: 'DLHC010012342025', cnr: 'DLHC010012342025' },
  { id: 'c2', team_id: 'tB', ext_id: 'DLHC010012342025', cnr: 'DLHC010012342025' },
  { id: 'c3', team_id: 'tA', ext_id: 'old', cnr: 'dlhc-0100-1234-2025' },
  { id: 'c4', team_id: 'tB', ext_id: 'x', diary_number: '342/2026' },
  { id: 'c5', team_id: 'tB', ext_id: 'y', case_number: '77', case_year: '2024', case_type: 'CS(OS)', court_code: 'DLHC', court_name: 'Delhi High Court' },
  { id: 'c6', team_id: 'tA', ext_id: 'z', case_number: '77', case_year: '2024', case_type: 'cs (os)', court_code: '', court_name: 'DELHI HIGH COURT' },
  { id: 'c7', team_id: 'tA', ext_id: 'DLHC|W.P.(C)|9|2020' },
]
const trackedPicks = [
  ['cnrBothTeamsOwnedB', pickA, ['tB']],
  ['cnrBothTeamsOwnedA', pickA, ['tA']],
  ['cnrNoOwned', pickA, []],
  ['canonCnr', { ...pickA, cnr: 'DLHC-0100-1234-2025' }, ['tA']],
  ['diary', { courtType: 'sc', diaryNumber: '342/2026' }, []],
  ['numberCourtCode', { courtCode: 'DLHC', courtName: 'Other', caseType: 'CS(OS)', caseNumber: '77', caseYear: '2024' }, ['tA']],
  ['numberCourtName', { courtCode: '', courtName: 'Delhi High Court', caseType: 'CS(OS)', caseNumber: '77', caseYear: '2024' }, ['tA']],
  ['extComputed', { courtCode: 'DLHC', caseType: 'W.P.(C)', caseNumber: '9', caseYear: '2020' }, []],
  ['nothing', { title: 'bare' }, ['tA']],
  ['noMatch', { courtCode: 'BHC', courtName: 'Bombay', caseType: 'WP', caseNumber: '1', caseYear: '2020' }, ['tA']],
  ['yearMismatch', { courtCode: 'DLHC', courtName: 'Delhi High Court', caseType: 'CS(OS)', caseNumber: '77', caseYear: '2023' }, []],
]
for (const [name, pick, owned] of trackedPicks) {
  const state = { cases: trackedRows, teams: [{ id: 'tA', owner_user_id: owned.includes('tA') ? 1 : 2 }, { id: 'tB', owner_user_id: owned.includes('tB') ? 1 : 2 }], user: { id: 1 } }
  add('findTrackedCase', { name, pick, cases: trackedRows, ownedTeamIds: owned }, trackCase.findTrackedCase(state, pick)?.id ?? null)
}

// lookupModel.js
for (const c of [{ caseType: 'W.P.(C)', caseNumber: '12', caseYear: '2025' }, { caseNumber: '12' }, { caseType: 'X' }, {},
  { title: 'RAM vs. SHYAM', caseType: 'T', caseNumber: '1' }, { title: '', caseType: 'CS', caseNumber: '3', caseYear: '2020' }]) {
  add('lookup.caseNumberOf', { record: c }, lookup.caseNumberOf(c))
  add('lookup.titleOf', { record: c }, lookup.titleOf(c))
}
for (const t of ['RFA', 'R.F.A.', 'CRL.A.', 'CRL A', 'LPA', 'CS(OS)', 'C.S. (COMM)', 'O.S.', 'W.P.(C)', 'FIRST APPEAL', 'CIVIL SUIT', 'ITA', 'MAC.APP.',
  'CO.APP', 'SA', 'SAO', 'CA', 'CAA', '', null, 'ARB.P.', 'SLP(C)', 'COS', 'CSA']) add('sideKeysFor', { caseType: t }, lookup.sideKeysFor(t))

// \u2500\u2500 Output \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
const json = JSON.stringify({ cases }, null, 1)
if (json.includes('"""#')) throw new Error('fixture contains the raw-string terminator')
const swift = `// Generated by scripts/generate-matter-fixtures.mjs from the platform's own matter modules
// (money/*.js, lib/projects/rules.js, courtNames.js, projectRecord.js, projectMeta.js,
// trackedCases.js, trackCase.js, lookupModel.js and the constants of ProjectBanner.jsx,
// shared.jsx and ProjectWorkspace.jsx). Do not edit by hand — regenerate it.
//
// Each case is one call: \`fn\` names it, \`input\` is what it was given and \`expected\` what it returned.

enum MatterGolden {
    static let json = #"""
${json}
"""#
}
`
const before = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null
if (before === swift) {
  console.log(`matter fixtures: up to date — ${cases.length} cases`)
  process.exit(0)
}
if (checkOnly) {
  console.error('matter fixtures: out of date — rerun without --check')
  process.exit(1)
}
fs.writeFileSync(out, swift)
console.log(`matter fixtures: wrote ${cases.length} cases`)

function* walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name)
    if (entry.isDirectory()) yield* walk(p)
    else if (/\.(js|jsx|mjs)$/.test(entry.name)) yield p
  }
}
