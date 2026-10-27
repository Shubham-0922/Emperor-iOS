#!/usr/bin/env node
// Regenerates the Fetch Orders and court-catalogue golden fixtures from the platform's own source.
//
//   node scripts/generate-lookup-fixtures.mjs <path-to-emperor-ai> [--check]
//
// Writes two files under Tests/EmperorCoreTests/Resources/parity/06-C/:
//
// - lookup.json: records as the platform's lookup builds them (`recordFromBundle`, cut by name
//   from court-scraper/lookup.js with the helpers it uses, and run over sample bundles: dates in
//   the court's formats, application status codes, fee amounts), and every answer of
//   src/components/lookup/lookupModel.js (`isDisposed`, `ago`, `roomOf`, `timelineOf`,
//   `summaryText`, `yearsOf`, `caseNumberOf`, `titleOf`) and of Dossier.jsx's `statusWord`, run
//   for real under Node. The app's `LookupRecord` decoding and `LookupModel` are held to them.
// - court-catalogue.json: src/lib/courts.js's static lists — the courts, the Supreme Court's case
//   types, NCLT/NCLAT benches and case types, the High Court state codes — so a change there
//   fails `CourtCatalogueGoldenTests` instead of drifting silently.
//
// Determinism: `today` is fixed ('2026-10-12') wherever the model takes it; the sample hearings
// lie in 2001 and 2099 so the lookup's own "upcoming" reading of the clock cannot move; the
// record's `fetchedAt` (the clock) is dropped. The process runs in UTC.
//
// `--check` writes nothing and exits 1 if either fixture differs.

process.env.TZ = 'UTC'

import { registerHooks } from 'node:module'
import { pathToFileURL, fileURLToPath } from 'node:url'
import fs from 'node:fs'
import path from 'node:path'

const platform = process.argv[2]
const checkOnly = process.argv.includes('--check')
if (!platform || !fs.existsSync(path.join(platform, 'court-scraper/lookup.js'))
  || !fs.existsSync(path.join(platform, 'src/components/lookup/lookupModel.js'))) {
  console.error('usage: generate-lookup-fixtures.mjs <path-to-emperor-ai> [--check]')
  process.exit(2)
}
const root = path.resolve(platform)
const src = path.join(root, 'src')
const outDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../Tests/EmperorCoreTests/Resources/parity/06-C')

// `@/` is the web's alias for src/. lucide-react resolves each icon to its own name; the zustand
// store is a stand-in nothing here calls.
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

const imp = (rel) => import(pathToFileURL(path.join(root, rel)).href)
const model = await imp('src/components/lookup/lookupModel.js')
const courts = await imp('src/lib/courts.js')

// ── Cut from source ─────────────────────────────────────────────────────────────────────────
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8')
const cut = (text, re, what) => {
  const m = text.match(re)
  if (!m) { console.error(`${what} not found — the cut is stale`); process.exit(1) }
  return m[0]
}
// court-scraper/lookup.js requires the scraper itself, which needs the server's packages; the
// record builder and its helpers are pure, so they are cut out by name and evaluated alone.
const lookupSource = read('court-scraper/lookup.js')
const pieces = [
  cut(lookupSource, /^const clean = [^\n]*\n/m, 'clean'),
  cut(lookupSource, /^function toIso\([\s\S]*?\n\}\n/m, 'toIso'),
  cut(lookupSource, /^const IA_STATUS = [^\n]*\n/m, 'IA_STATUS'),
  cut(lookupSource, /^const iaStatus = [^\n]*\n/m, 'iaStatus'),
  cut(lookupSource, /^function recordFromBundle\([\s\S]*?\n\}\n/m, 'recordFromBundle'),
]
const recordFromBundle = new Function(`${pieces.join('\n')}\nreturn recordFromBundle`)()
const dossierSource = read('src/components/lookup/Dossier.jsx')
const statusWord = new Function(`${cut(dossierSource, /^const WORDS = [^\n]*\n/m, 'WORDS')}
${cut(dossierSource, /^const statusWord = [^\n]*\n/m, 'statusWord')}
return statusWord`)()

// ── Records ─────────────────────────────────────────────────────────────────────────────────
const TODAY = '2026-10-12'
const samples = [
  ['full', {
    courtType: 'hc', courtCode: 'hc-delhi', courtName: 'High Court — Delhi', caseType: 'W.P.(C)', caseNumber: '4410',
    caseYear: '2025', cnr: 'DLHC010044102025', title: 'Mehta Traders vs. Union of India', status: 'Pending', judge: 'HON\'BLE MR. JUSTICE A',
  }, {
    cnr: 'DLHC010044102025', status: 'Pending', stage: 'ADMISSION', bench: 'HON\'BLE MS. JUSTICE R. MENON', filingDate: '01-03-2025',
    category: 'Writ', petitioners: ['MEHTA TRADERS'], respondents: ['UNION OF INDIA', 'COMMISSIONER OF CUSTOMS'],
    petitionerAdvocates: ['A. K. MEHTA', 'S. RAO'], respondentAdvocates: ['ASG'],
    hearings: [
      { date: '15-01-2099', purpose: 'FOR ADMISSION', judges: 'COURT NO. 4', courtNo: '4', itemNo: '12' },
      { date: '2026-09-30', purpose: 'TO BE LISTED IN COURT NO.42', courtNo: 'Principal Seat Hall 2', stage: 'ADMISSION' },
      { date: '05/03/2025', purpose: null, courtNo: '51A' },
      { date: 'not a date', purpose: 'DROPPED' },
    ],
    orders: [
      { date: '30-09-2026', title: 'O', pdfUrl: 'https://delhihighcourt.nic.in/orders/1.pdf' },
      { date: '2025-03-05', title: 'J', pdfUrl: null },
      { date: '2025-03-05', title: 'Order on IA', pdfUrl: 'ejagriti-order:77' },
      { date: null, title: 'Undated', pdfUrl: 'https://example.org/x.pdf' },
      { date: null, title: 'Nothing', pdfUrl: null },
    ],
    ias: [{ number: 'IA 1/2025', particular: 'EXEMPTION', filingDate: '02-03-2025', status: 'D', remark: 'Allowed', filedBy: 'Petitioner' },
      { number: 'IA 2/2025', particular: 'STAY', filingDate: null, status: 'X', remark: null }],
    connected: [{ caseNo: 'CS 12/2020', court: 'District Court', state: 'Delhi', orderDate: '12/12/2020', cnr: 'DLCT01' }],
    courtFees: [{ head: 'Court fee', amount: '1,250' }, { head: 'Copying fee', amount: 'Rs 500' }, { head: 'Process fee', amount: null }, { head: 'Other', amount: 'nil' }],
  }],
  ['sparse', { courtType: 'sc', courtName: 'Supreme Court of India', diaryNumber: '41207/2025', title: 'Rao v. Union of India' },
    { status: 'Disposed', hearings: [{ date: '2001-02-03', purpose: 'JUDGMENT' }] }],
  ['empty-parties', { courtType: 'nclt', courtName: 'NCLT Mumbai Bench', caseType: 'C.P. (IB)', caseNumber: '1187', caseYear: '2024', status: 'Pending', stage: 'Reserved' },
    { orders: [{ date: '2024-02-12', title: 'Admission order', pdfUrl: 'https://nclt.gov.in/a.pdf' }, { date: '2023-12-01', title: 'Notice', pdfUrl: 'https://nclt.gov.in/b.pdf' },
      { date: '2024-01-05', title: 'Adjourned', pdfUrl: null }] }],
]
const records = samples.map(([id, card, bundle]) => {
  const record = recordFromBundle(bundle, card)
  delete record.fetchedAt
  return { id, card, record }
})

// ── Model ───────────────────────────────────────────────────────────────────────────────────
const cases = []
const add = (fn, input, expected) => cases.push({ fn, input, expected: expected === undefined ? null : expected })
for (const s of ['Pending', 'Disposed', 'DISPOSED OF', 'Decided', 'Dismissed in default', 'Closed', 'withdrawn', 'Allowed', '', null, 'Part heard'])
  add('isDisposed', { status: s }, model.isDisposed({ status: s }))
for (const s of ['Pending', 'Disposed', 'Dismissed', 'Allowed', 'Withdrawn', 'Part Heard', 'pending', '', null])
  add('statusWord', { status: s }, statusWord(s) ?? null)
for (const d of ['2026-10-12', '2026-10-13', '2026-10-11', '2026-10-25', '2026-10-26', '2026-09-28', '2026-12-11', '2026-08-13',
  '2027-10-12', '2024-10-12', '2025-10-13', '2026-10-30', '', null, 'garbage', '2026-10-12T20:00:00.000Z'])
  add('ago', { day: d, today: TODAY }, model.ago(d, TODAY))
for (const n of ['4', '51A', ' 12 ', 'Principal Seat Hall 2', 'COURT NO. 3', '', null, '4AB', 'VC'])
  add('roomOf', { courtNo: n }, model.roomOf(n))
for (const r of records) {
  add('timelineOf', { recordId: r.id, today: TODAY }, model.timelineOf(r.record, TODAY))
  add('summaryText', { recordId: r.id, today: TODAY }, model.summaryText(r.record, TODAY))
  add('summaryText', { recordId: r.id, today: '2000-01-01' }, model.summaryText(r.record, '2000-01-01'))
  add('yearsOf', { recordId: r.id }, model.yearsOf(r.record.orders))
  add('caseNumberOf', { recordId: r.id }, model.caseNumberOf(r.record.case))
  add('titleOf', { recordId: r.id }, model.titleOf(r.record.case))
  add('sidesOf', { recordId: r.id }, model.sidesOf(r.record.parties))
}

// ── The catalogue ───────────────────────────────────────────────────────────────────────────
const catalogue = {
  courts: courts.COURTS,
  scCaseTypes: courts.SC_CASE_TYPES,
  ncltBenches: courts.NCLT_BENCHES,
  ncltCaseTypes: courts.NCLT_CASE_TYPES,
  nclatBenches: courts.NCLAT_BENCHES,
  nclatCaseTypes: courts.NCLAT_CASE_TYPES,
  hcStateCode: courts.HC_STATE_CODE,
}

// ── Output ──────────────────────────────────────────────────────────────────────────────────
let stale = false
const write = (name, value) => {
  const out = path.join(outDir, name)
  const text = JSON.stringify(value, null, 1) + '\n'
  const before = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null
  if (before === text) { console.log(`${name}: up to date`); return }
  if (checkOnly) { console.error(`${name}: out of date — rerun without --check`); stale = true; return }
  fs.mkdirSync(outDir, { recursive: true })
  fs.writeFileSync(out, text)
  console.log(`${name}: written`)
}
write('lookup.json', { today: TODAY, records, cases })
write('court-catalogue.json', catalogue)
console.log(`${records.length} records, ${cases.length} model cases, ${catalogue.courts.length} courts`)
if (stale) process.exit(1)

function* walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name)
    if (entry.isDirectory()) yield* walk(p)
    else if (/\.(js|jsx|mjs)$/.test(entry.name)) yield p
  }
}
